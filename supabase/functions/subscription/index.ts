// Links a verified StoreKit 2 transaction to the signed-in user and returns their plan.
// The app sends Transaction.jwsRepresentation after a purchase, restore or renewal. Ownership
// follows the subscription (originalTransactionId): the latest verified presenter owns it, so a
// purchase made while anonymous moves to the Apple account after sign-in or restore.
// Refunded or revoked subscriptions stay revoked, so an old JWS cannot be replayed; only a purchase
// made after the refund (a resubscription) lifts it.
// Paid allowances are counted per subscription (see the `ai` function), so moving one between
// accounts doesn't reset them.
// Local StoreKit testing ("Xcode" environment, unsigned) is accepted only for user ids in
// XCODE_TEST_USERS, and kept apart from real subscriptions. Leave that variable unset in production.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyAppleJWS } from "../_shared/appstore.ts";
import { BUNDLE_ID, findSubscription, later, PLANS, recomputePlan, saveSubscription, time } from "../_shared/subscriptions.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const XCODE_TEST_USERS = new Set(
  (Deno.env.get("XCODE_TEST_USERS") ?? "").split(",").map((id) => id.trim().toLowerCase()).filter(Boolean),
);

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const { data: auth, error: authError } = await supabase.auth.getUser(token);
  if (authError || !auth.user) return json({ error: "unauthorized" }, 401);
  const userId = auth.user.id;

  if (Number(req.headers.get("content-length") ?? 0) > 40_000) return json({ error: "bad_request" }, 413);
  const body = await req.json().catch(() => ({}));
  if (typeof body.signedTransaction !== "string" || body.signedTransaction.length > 20_000) {
    return json({ error: "bad_request" }, 400);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await verifyAppleJWS(body.signedTransaction, { allowXcode: XCODE_TEST_USERS.has(userId.toLowerCase()) });
  } catch (err) {
    console.warn("rejected transaction", userId, err instanceof Error ? err.message : err);
    return json({ error: "unverified" }, 422);
  }

  const productId = String(payload.productId ?? "");
  const plan = PLANS[productId];
  if (payload.bundleId !== BUNDLE_ID || !plan) return json({ error: "wrong_product" }, 422);

  const environment = String(payload.environment ?? "Production");
  const isXcode = environment === "Xcode";
  const rawOriginal = String(payload.originalTransactionId ?? payload.transactionId ?? "");
  if (!rawOriginal) return json({ error: "bad_request" }, 400);
  // Xcode transactions are unsigned: they get their own namespace and none of their dates are trusted.
  const original = isXcode ? `xcode:${rawOriginal}` : rawOriginal;
  const signedAt = new Date(isXcode ? Date.now() : Number(payload.signedDate ?? Date.now())).toISOString();
  const purchasedAt = Number(payload.purchaseDate ?? 0);
  const revocationDate = !isXcode && payload.revocationDate ? new Date(Number(payload.revocationDate)).toISOString() : null;
  let expires = payload.expiresDate ? new Date(Number(payload.expiresDate)).toISOString() : null;
  if (isXcode && expires) {
    // Local testing never grants more than a day.
    expires = new Date(Math.min(new Date(expires).getTime(), Date.now() + 86_400_000)).toISOString();
  }

  try {
    const existing = await findSubscription(supabase, original);
    // A refunded earlier period doesn't revoke a subscription that has renewed since.
    const refundsCurrentPeriod = !existing?.expires_at || !expires || time(expires) >= time(existing.expires_at) - 60_000;
    const revocation = refundsCurrentPeriod ? revocationDate : null;
    // A refund sticks unless this transaction was bought after it (the person subscribed again).
    const resubscribed = existing?.revoked && !revocation && purchasedAt > time(existing.revoked_at ?? existing.last_signed_at);
    if (existing?.revoked && !resubscribed) {
      return json({ plan: await recomputePlan(supabase, userId), revoked: true });
    }
    const newer = !existing || time(signedAt) >= time(existing.last_signed_at);
    const previousOwner = existing?.user_id ?? null;
    await saveSubscription(supabase, {
      original_transaction_id: original,
      user_id: userId,
      product_id: newer ? productId : existing!.product_id,
      plan: newer ? plan : existing!.plan,
      expires_at: resubscribed ? expires : later(existing?.expires_at ?? null, expires),
      environment,
      revoked: Boolean(revocation),
      revoked_at: revocation ?? (resubscribed ? null : existing?.revoked_at ?? null),
      last_signed_at: later(existing?.last_signed_at ?? null, signedAt)!,
    });
    if (previousOwner && previousOwner !== userId) await recomputePlan(supabase, previousOwner);
    const current = await recomputePlan(supabase, userId);
    return json({ plan: current, expiresAt: expires });
  } catch (err) {
    console.error("subscription", err instanceof Error ? err.message : err);
    return json({ error: "server_error" }, 500);
  }
});
