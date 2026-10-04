// App Store Server Notifications V2. Apple calls this URL on renewals, expirations, refunds and
// revocations, so plans stay correct even when the app is not opened. Set the URL in
// App Store Connect → App Information → App Store Server Notifications (Version 2), for both
// Production and Sandbox. No JWT here: Apple authenticates by signing the payload, which we verify.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyAppleJWS } from "../_shared/appstore.ts";
import { BUNDLE_ID, findSubscription, isUUID, later, PLANS, recomputePlan, saveSubscription, time } from "../_shared/subscriptions.ts";
import { rewardPurchase } from "../_shared/referrals.ts";

const ACTIVE = new Set(["SUBSCRIBED", "DID_RENEW", "OFFER_REDEEMED", "RENEWAL_EXTENDED", "REFUND_REVERSED", "DID_CHANGE_RENEWAL_PREF"]);
const ENDED = new Set(["EXPIRED", "GRACE_PERIOD_EXPIRED"]);
const REVOKED = new Set(["REFUND", "REVOKE"]);

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  if (Number(req.headers.get("content-length") ?? 0) > 200_000) return new Response("too large", { status: 413 });
  const raw = await req.text();
  if (raw.length > 200_000) return new Response("too large", { status: 413 });

  let notification: Record<string, unknown>;
  let transaction: Record<string, unknown>;
  let renewal: Record<string, unknown> | null = null;
  try {
    const body = JSON.parse(raw);
    notification = await verifyAppleJWS(String(body.signedPayload ?? ""));
    const data = (notification.data ?? {}) as Record<string, unknown>;
    if (data.bundleId !== BUNDLE_ID || typeof data.signedTransactionInfo !== "string") {
      return new Response("ignored", { status: 200 });
    }
    transaction = await verifyAppleJWS(data.signedTransactionInfo);
    if (typeof data.signedRenewalInfo === "string") renewal = await verifyAppleJWS(data.signedRenewalInfo);
  } catch (err) {
    console.warn("rejected notification", err instanceof Error ? err.message : err);
    return new Response("unverified", { status: 400 });
  }

  const type = String(notification.notificationType ?? "");
  const original = String(transaction.originalTransactionId ?? "");
  const plan = PLANS[String(transaction.productId ?? "")];
  if (!original || !plan) return new Response("ignored", { status: 200 });

  try {
    const existing = await findSubscription(supabase, original);
    const signedAt = new Date(Number(notification.signedDate ?? Date.now())).toISOString();
    // Apple may retry or reorder notifications: one older than the last applied notification is
    // stale (also a late REFUND after a REFUND_REVERSED). Times of transactions the app presents are
    // kept separately, so they can't make a pending notification look stale.
    if (existing && time(existing.last_notification_at) >= time(signedAt)) {
      return new Response("stale", { status: 200 });
    }
    // A refund of an earlier period (the subscription has since renewed) doesn't end the
    // period the person is paying for now.
    const refundsCurrentPeriod = !existing?.expires_at || !transaction.expiresDate ||
      Number(transaction.expiresDate) >= time(existing.expires_at) - 60_000;
    const isRevocation = (REVOKED.has(type) || Boolean(transaction.revocationDate)) && refundsCurrentPeriod;

    const token = String(transaction.appAccountToken ?? "").toLowerCase();
    // A known subscription keeps its owner (none after that account was deleted); a new one may
    // name its buyer through appAccountToken.
    const owner = existing ? existing.user_id : (isUUID(token) ? token : null);
    const expires = transaction.expiresDate ? new Date(Number(transaction.expiresDate)).toISOString() : null;

    let row = {
      original_transaction_id: original,
      user_id: owner,
      product_id: String(transaction.productId),
      plan,
      expires_at: existing?.expires_at ?? expires,
      environment: String(transaction.environment ?? "Production"),
      revoked: existing?.revoked ?? false,
      revoked_at: existing?.revoked_at ?? null,
      last_signed_at: later(existing?.last_signed_at ?? null, signedAt)!,
      last_notification_at: later(existing?.last_notification_at ?? null, signedAt),
    };
    if (isRevocation) {
      const when = transaction.revocationDate ? new Date(Number(transaction.revocationDate)).toISOString() : signedAt;
      row = { ...row, revoked: true, revoked_at: when };
    } else if (ACTIVE.has(type)) {
      // Another product (an upgrade or crossgrade) brings its own expiry.
      const switched = existing && existing.product_id !== row.product_id;
      row = { ...row, revoked: false, revoked_at: null, expires_at: switched ? expires : later(existing?.expires_at ?? null, expires) };
    } else if (ENDED.has(type)) {
      row = { ...row, expires_at: expires };
    } else if (type === "DID_FAIL_TO_RENEW" && renewal?.gracePeriodExpiresDate) {
      row = { ...row, expires_at: new Date(Number(renewal.gracePeriodExpiresDate)).toISOString() };
    }

    try {
      await saveSubscription(supabase, row);
    } catch (err) {
      // The owner named by the token no longer exists (foreign key violation): keep the record
      // without an owner. Any other error is retried by Apple.
      if ((err as { code?: string })?.code !== "23503") throw err;
      row = { ...row, user_id: null };
      await saveSubscription(supabase, row);
    }
    await recomputePlan(supabase, row.user_id);
    if (ACTIVE.has(type) && !row.revoked) {
      await rewardPurchase(supabase, row.user_id, transaction).catch((err) => console.warn("referral", err));
    }
    console.log("notification", type, notification.subtype ?? "", original, row.revoked ? "revoked" : row.expires_at);
    return new Response("ok", { status: 200 });
  } catch (err) {
    console.error("notification", err instanceof Error ? err.message : err);
    return new Response("retry", { status: 500 });
  }
});
