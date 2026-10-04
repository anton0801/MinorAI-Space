// Remote notifications through Apple (APNs), sent straight from the edge functions; no other
// service is involved. Needs APNS_KEY_ID and APNS_PRIVATE_KEY (the .p8 of a key with Apple Push
// Notifications service enabled) and the team id in APPLE_TEAM_ID (or APNS_TEAM_ID) as secrets.
// Without them nothing is sent.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { BUNDLE_ID } from "./apple.ts";
import { appleKey, signJWT } from "./es256.ts";
import type { Localized, PushText } from "./pushText.ts";

export type PushTopic = "collab" | "account";

export interface PushMessage {
  text: Localized;
  route?: string; // minorai://… opened when the notification is tapped
  thread?: string; // groups notifications about the same thing
}

let cached: { token: string; at: number } | null = null;

export function pushConfigured(): boolean {
  return appleKey("APNS") !== null;
}

// Apple wants a new provider token at most every 20 minutes and accepts one for an hour.
export async function providerToken(now = Date.now()): Promise<string | null> {
  if (cached && now - cached.at < 40 * 60_000) return cached.token;
  const key = appleKey("APNS");
  if (!key) return null;
  const token = await signJWT(key, { iss: key.teamID, iat: Math.floor(now / 1000) });
  cached = { token, at: now };
  return token;
}

export function apnsPayload(text: PushText, message: Pick<PushMessage, "route" | "thread">): Record<string, unknown> {
  return {
    aps: {
      alert: { title: text.title.slice(0, 120), body: text.body.slice(0, 400) },
      sound: "default",
      ...(message.thread ? { "thread-id": message.thread } : {}),
    },
    ...(message.route ? { route: message.route } : {}),
  };
}

interface Delivery {
  ok: boolean;
  status: number;
  reason?: string;
}

async function deliver(jwt: string, token: string, sandbox: boolean, body: string): Promise<Delivery> {
  const host = sandbox ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  try {
    const res = await fetch(`${host}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 86_400),
        "content-type": "application/json",
      },
      body,
      signal: AbortSignal.timeout(10_000),
    });
    if (res.ok) {
      await res.body?.cancel();
      return { ok: true, status: res.status };
    }
    const reason = (await res.json().catch(() => ({}))).reason;
    return { ok: false, status: res.status, reason: typeof reason === "string" ? reason : undefined };
  } catch (err) {
    console.warn("apns", err instanceof Error ? err.message : err);
    return { ok: false, status: 0 };
  }
}

// Sends to every device of these people that wants this topic, and returns how many got it.
// Never throws: a notification is never worth failing the request it comes from.
export async function sendPush(supabase: SupabaseClient, users: string[], topic: PushTopic, message: PushMessage): Promise<number> {
  try {
    if (!users.length) return 0;
    const jwt = await providerToken();
    if (!jwt) return 0;
    const { data } = await supabase
      .from("push_tokens")
      .select("token, sandbox, language")
      .in("user_id", users.slice(0, 50))
      .eq(topic, true);
    const rows = (data ?? []) as { token: string; sandbox: boolean; language: string }[];
    const results = await Promise.all(rows.map(async (row) => {
      const body = JSON.stringify(apnsPayload(message.text(row.language), message));
      let result = await deliver(jwt, row.token, row.sandbox, body);
      // A build signed for the other environment (a development build of a release, or the other
      // way round): try there once and remember it.
      if (result.reason === "BadDeviceToken") {
        const other = await deliver(jwt, row.token, !row.sandbox, body);
        if (other.ok) await supabase.from("push_tokens").update({ sandbox: !row.sandbox }).eq("token", row.token);
        result = other;
      }
      if (!result.ok && (result.status === 410 || ["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"].includes(result.reason ?? ""))) {
        await supabase.from("push_tokens").delete().eq("token", row.token);
      }
      if (!result.ok && result.status !== 410) console.warn("apns refused", result.status, result.reason ?? "");
      return result.ok;
    }));
    return results.filter(Boolean).length;
  } catch (err) {
    console.warn("push", err instanceof Error ? err.message : err);
    return 0;
  }
}

// At most one notification on this topic per person per `seconds`.
export async function pushAllowed(supabase: SupabaseClient, user: string, topic: string, seconds: number): Promise<boolean> {
  const { data, error } = await supabase.rpc("push_allowed", { p_user: user, p_topic: topic, p_seconds: seconds });
  return !error && data === true;
}

// Lets a notification finish after the response is sent, where the runtime supports it.
export function inBackground(work: Promise<unknown>) {
  const runtime = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } }).EdgeRuntime;
  const guarded = work.catch((err) => console.warn("background", err instanceof Error ? err.message : err));
  if (runtime?.waitUntil) runtime.waitUntil(guarded);
}
