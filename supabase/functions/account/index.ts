// Account actions that need the service role.
// - {"action":"usage"}: this month's AI allowance (with what it went to) and request counts.
// - {"action":"invite"}: the person's invitation code, their friends and free days of Plus.
// - {"action":"redeem","code":"…","deviceToken":"…"}: take a friend's invitation (new accounts only).
// - {"action":"claim_discount","product":"…"}: an earned discount as a one-time App Store offer code.
// - {"action":"apple_code","code":"…"}: keeps the Sign in with Apple refresh token so it can be revoked later.
// - {"action":"delete"}: removes shared and synced map images, revokes the Apple token, then deletes
//   the user (profiles, usage, synced maps, shared link rows and Apple tokens go with it through
//   ON DELETE CASCADE).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { exchangeCode, revoke } from "../_shared/apple.ts";
import { DeviceCheckError, deviceCheckConfigured, deviceTaken, markDevice } from "../_shared/devicecheck.ts";
import { FETCH_LIMITS, LIMITS } from "../_shared/models.ts";
import { budgetMicros, currentSubscription } from "../_shared/plan.ts";
import { cleanCode, DISCOUNT_PERCENT, DISCOUNT_PRODUCTS, INVITE_DAYS, INVITE_LIMIT, newCode, redeemURL } from "../_shared/referrals.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
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

  if (Number(req.headers.get("content-length") ?? 0) > 10_000) return json({ error: "bad_request" }, 413);
  const body = await req.json().catch(() => ({}));

  try {
    if (body.action === "usage") return json(await usage(userId));
    if (body.action === "invite") return await invite(auth.user);
    if (body.action === "redeem") return await redeem(auth.user, body, req.headers.get("x-device-id"));
    if (body.action === "claim_discount") return await claimDiscount(auth.user, body);
  } catch (err) {
    console.error(String(body.action), err instanceof Error ? err.message : err);
    return json({ error: "server_error" }, 500);
  }

  if (body.action === "apple_code") {
    const code = String(body.code ?? "");
    if (!code || code.length > 2000) return json({ error: "bad_request" }, 400);
    try {
      const refreshToken = await exchangeCode(code);
      if (refreshToken) {
        await supabase.from("apple_tokens").upsert({ user_id: userId, refresh_token: refreshToken });
      }
      return json({ stored: Boolean(refreshToken) });
    } catch (err) {
      console.error("apple_code", err instanceof Error ? err.message : err);
      return json({ error: "server_error" }, 500);
    }
  }

  if (body.action !== "delete") return json({ error: "bad_request" }, 400);

  // Shared map images are public files; remove them before the rows disappear.
  const { data: links } = await supabase.from("shared_links").select("path").eq("user_id", userId);
  const paths = (links ?? []).map((row: { path: string }) => row.path);
  // Early builds uploaded straight to "<user id>/…" in the bucket; remove those too.
  const { data: legacy } = await supabase.storage.from("shared").list(userId, { limit: 1000 });
  for (const file of legacy ?? []) paths.push(`${userId}/${file.name}`);
  if (paths.length) {
    const { error } = await supabase.storage.from("shared").remove(paths);
    if (error) console.warn("shared cleanup", error.message);
  }

  // Pictures of synced maps are private files; the map rows go with the user (ON DELETE CASCADE).
  for (let round = 0; round < 50; round++) {
    const { data: files } = await supabase.storage.from("map-images").list(userId, { limit: 1000 });
    if (!files?.length) break;
    const { error: removeError } = await supabase.storage.from("map-images").remove(files.map((f: { name: string }) => `${userId}/${f.name}`));
    if (removeError) {
      console.warn("map images cleanup", removeError.message);
      break;
    }
    if (files.length < 1000) break;
  }

  // Pictures of maps this person shared for editing (the maps themselves go with the user).
  const { data: owned } = await supabase.from("collab_maps").select("id").eq("owner", userId);
  for (const map of owned ?? []) {
    for (let round = 0; round < 10; round++) {
      const { data: files } = await supabase.storage.from("collab-images").list(map.id, { limit: 1000 });
      if (!files?.length) break;
      const { error: removeError } = await supabase.storage.from("collab-images").remove(files.map((f: { name: string }) => `${map.id}/${f.name}`));
      if (removeError) {
        console.warn("collab images cleanup", removeError.message);
        break;
      }
      if (files.length < 1000) break;
    }
  }

  const { data: apple } = await supabase.from("apple_tokens").select("refresh_token").eq("user_id", userId).maybeSingle();
  if (apple?.refresh_token) {
    const revoked = await revoke(apple.refresh_token).catch(() => false);
    if (!revoked) console.warn("apple token not revoked", userId);
  }

  const { error } = await supabase.auth.admin.deleteUser(userId);
  if (error) {
    console.error("delete user", error.message);
    return json({ error: "server_error" }, 500);
  }
  return json({ deleted: true });
});

// ---------- limits ----------

function count(value: unknown): number {
  const n = Number(value ?? 0);
  return Number.isFinite(n) ? n : 0;
}

// Counted where the `ai` function counts: a paid plan on its subscription, everything else on the
// account. Link and video fetches are always on the account.
async function usage(userId: string) {
  const active = await currentSubscription(supabase, userId);
  const period = new Date().toISOString().slice(0, 7);
  const { data: own } = await supabase.from("usage").select("*").eq("user_id", userId).eq("period", period).maybeSingle();
  let row: Record<string, unknown> = own ?? {};
  if (active.subscription) {
    const { data } = await supabase.from("subscription_usage").select("*")
      .eq("original_transaction_id", active.subscription).eq("period", period).maybeSingle();
    row = data ?? {};
  }
  const limits = LIMITS[active.plan];
  const now = new Date();
  const resetsAt = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
  const counted = (kind: "maps" | "decks" | "expands" | "chats" | "images") => ({ used: count(row[kind]), limit: limits[kind] });
  return {
    plan: active.plan,
    bonusUntil: active.bonusUntil ?? null,
    resetsAt: resetsAt.toISOString(),
    allowance: {
      limit: budgetMicros(active),
      used: count(row.spend_micros),
      areas: {
        maps: count(row.spend_maps),
        decks: count(row.spend_decks),
        chat: count(row.spend_chat),
        images: count(row.spend_images),
      },
    },
    counts: {
      maps: counted("maps"),
      decks: counted("decks"),
      expands: counted("expands"),
      chats: counted("chats"),
      images: counted("images"),
      fetches: { used: count(own?.fetches), limit: FETCH_LIMITS[active.plan] },
    },
  };
}

// ---------- invitations ----------

type User = { id: string; is_anonymous?: boolean; created_at: string };

const REDEEM_DAYS = 14;

async function inviteCode(userId: string): Promise<string> {
  for (let attempt = 0; attempt < 5; attempt++) {
    const { data } = await supabase.from("referral_codes").select("code").eq("user_id", userId).maybeSingle();
    if (data?.code) return data.code;
    const { error } = await supabase.from("referral_codes").insert({ user_id: userId, code: newCode() });
    // 23505: the code is taken (try another) or a parallel request made one (read it).
    if (error && error.code !== "23505") throw error;
  }
  throw new Error("no_code");
}

async function invite(user: User): Promise<Response> {
  if (user.is_anonymous) return json({ error: "sign_in_required" }, 403);
  const code = await inviteCode(user.id);
  const { data: friends } = await supabase.from("referrals")
    .select("join_rewarded_at, purchase_rewarded_at, discount_code, discount_product")
    .eq("inviter", user.id).limit(100);
  const { data: mine } = await supabase.from("referrals").select("created_at").eq("invitee", user.id).maybeSingle();
  const active = await currentSubscription(supabase, user.id);
  const { data: profile } = await supabase.from("profiles").select("bonus_days").eq("id", user.id).maybeSingle();
  // Places used on the code count every friend who ever joined (also ones who later deleted
  // their account), like the check when a code is used.
  const { data: codeRow } = await supabase.from("referral_codes").select("redeemed").eq("user_id", user.id).maybeSingle();
  const rows = (friends ?? []) as {
    join_rewarded_at: string | null;
    purchase_rewarded_at: string | null;
    discount_code: string | null;
    discount_product: string | null;
  }[];
  const young = Date.parse(user.created_at) > Date.now() - REDEEM_DAYS * 86_400_000;
  return json({
    code,
    link: `https://minorai.site/invite/#c=${code}`,
    friends: Math.max(rows.length, count(codeRow?.redeemed)),
    active: rows.filter((r) => r.join_rewarded_at).length,
    subscribed: rows.filter((r) => r.purchase_rewarded_at).length,
    limit: INVITE_LIMIT,
    discountPercent: DISCOUNT_PERCENT,
    discountsAvailable: rows.filter((r) => r.purchase_rewarded_at && !r.discount_code).length,
    discounts: rows.filter((r) => r.discount_code).map((r) => ({
      code: r.discount_code,
      product: r.discount_product,
      url: redeemURL(r.discount_code!),
    })),
    bonusUntil: active.bonusUntil ?? null,
    bonusDays: count(profile?.bonus_days),
    redeemed: Boolean(mine),
    canRedeem: !mine && young,
    days: INVITE_DAYS,
  });
}

const REDEEM_ERRORS: Record<string, number> = {
  invite_not_found: 404,
  invite_own_code: 409,
  invite_too_late: 409,
  invite_used: 409,
  invite_device_used: 409,
  invite_limit: 409,
  sign_in_required: 403,
};

async function deviceHash(raw: string | null): Promise<string | null> {
  if (!raw || !/^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$/.test(raw)) return null;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`minor-invite:${raw.toLowerCase()}`));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

// A friend's code. Apple's DeviceCheck (when configured) makes sure this iPhone never took an
// invitation before, even with another account or after reinstalling the app.
async function redeem(user: User, body: Record<string, unknown>, deviceHeader: string | null): Promise<Response> {
  if (user.is_anonymous) return json({ error: "sign_in_required" }, 403);
  const code = cleanCode(body.code);
  if (!code) return json({ error: "invite_not_found" }, 404);
  const device = await deviceHash(deviceHeader);
  if (!device) return json({ error: "device_required" }, 400);

  const token = typeof body.deviceToken === "string" && body.deviceToken.length < 8_000 ? body.deviceToken : null;
  let sandbox = body.sandbox === true;
  let verified = false;
  if (deviceCheckConfigured()) {
    if (!token) return json({ error: "device_check_required" }, 400);
    try {
      const checked = await deviceTaken(token, sandbox);
      if (checked.taken) return json({ error: "invite_device_used" }, 409);
      sandbox = checked.sandbox;
      verified = true;
    } catch (err) {
      // A key without DeviceCheck shouldn't block every invitation: the device hash still
      // applies, and the log says what to fix.
      if (err instanceof DeviceCheckError && err.message === "key") {
        console.error("devicecheck: the key isn't enabled for DeviceCheck; set DEVICECHECK_KEY_ID / DEVICECHECK_PRIVATE_KEY");
      } else {
        console.warn("devicecheck", err instanceof DeviceCheckError ? err.message : err);
        return json({ error: "device_check_failed" }, 503);
      }
    }
  }

  const { data, error } = await supabase.rpc("redeem_referral", { p_invitee: user.id, p_code: code, p_device: device });
  if (error) {
    const status = REDEEM_ERRORS[error.message];
    if (status) return json({ error: error.message }, status);
    throw error;
  }
  if (token && verified) {
    await markDevice(token, sandbox).catch((err) => console.warn("devicecheck mark", err instanceof Error ? err.message : err));
  }
  const active = await currentSubscription(supabase, user.id);
  return json({ days: count((data as { days?: number } | null)?.days), bonusUntil: active.bonusUntil ?? null });
}

// The inviter turns an earned discount into an offer code for the subscription they pick.
async function claimDiscount(user: User, body: Record<string, unknown>): Promise<Response> {
  if (user.is_anonymous) return json({ error: "sign_in_required" }, 403);
  const product = String(body.product ?? "");
  if (!DISCOUNT_PRODUCTS.includes(product)) return json({ error: "bad_request" }, 400);
  const { data, error } = await supabase.rpc("claim_referral_discount", { p_inviter: user.id, p_product: product });
  if (error) {
    if (error.message === "no_discount") return json({ error: "no_discount" }, 409);
    if (error.message === "no_codes") {
      console.warn("offer codes ran out", product);
      return json({ error: "no_codes" }, 503);
    }
    throw error;
  }
  const code = String(data);
  return json({ code, product, url: redeemURL(code) });
}
