// ../../functions/_shared/apple.ts
var BUNDLE_ID = "com.minorailifegroup.MinorAI";

// ../../functions/_shared/es256.ts
function appleKey(prefix) {
  const keyID = Deno.env.get(`${prefix}_KEY_ID`);
  const privateKey = Deno.env.get(`${prefix}_PRIVATE_KEY`);
  const teamID = Deno.env.get(`${prefix}_TEAM_ID`) ?? Deno.env.get("APPLE_TEAM_ID");
  return keyID && privateKey && teamID ? { keyID, teamID, privateKey } : null;
}
function base64url(bytes) {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
async function signJWT(key, claims) {
  const pem = key.privateKey.replace(/\\n/g, "\n").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const signer = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const encoder = new TextEncoder();
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: key.keyID })));
  const payload = base64url(encoder.encode(JSON.stringify(claims)));
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, signer, encoder.encode(`${header}.${payload}`))
  );
  return `${header}.${payload}.${base64url(signature)}`;
}

// ../../functions/_shared/push.ts
var cached = null;
function pushConfigured() {
  return appleKey("APNS") !== null;
}
async function providerToken(now = Date.now()) {
  if (cached && now - cached.at < 40 * 6e4) return cached.token;
  const key = appleKey("APNS");
  if (!key) return null;
  const token = await signJWT(key, { iss: key.teamID, iat: Math.floor(now / 1e3) });
  cached = { token, at: now };
  return token;
}
function apnsPayload(text, message) {
  return {
    aps: {
      alert: { title: text.title.slice(0, 120), body: text.body.slice(0, 400) },
      sound: "default",
      ...message.thread ? { "thread-id": message.thread } : {}
    },
    ...message.route ? { route: message.route } : {}
  };
}
async function deliver(jwt, token, sandbox, body) {
  const host = sandbox ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  try {
    const res = await fetch(`${host}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": String(Math.floor(Date.now() / 1e3) + 86400),
        "content-type": "application/json"
      },
      body,
      signal: AbortSignal.timeout(1e4)
    });
    if (res.ok) {
      await res.body?.cancel();
      return { ok: true, status: res.status };
    }
    const reason = (await res.json().catch(() => ({}))).reason;
    return { ok: false, status: res.status, reason: typeof reason === "string" ? reason : void 0 };
  } catch (err) {
    console.warn("apns", err instanceof Error ? err.message : err);
    return { ok: false, status: 0 };
  }
}
async function sendPush(supabase, users, topic, message) {
  try {
    if (!users.length) return 0;
    const jwt = await providerToken();
    if (!jwt) return 0;
    const { data } = await supabase.from("push_tokens").select("token, sandbox, language").in("user_id", users.slice(0, 50)).eq(topic, true);
    const rows = data ?? [];
    const results = await Promise.all(rows.map(async (row) => {
      const body = JSON.stringify(apnsPayload(message.text(row.language), message));
      let result = await deliver(jwt, row.token, row.sandbox, body);
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
async function pushAllowed(supabase, user, topic, seconds) {
  const { data, error } = await supabase.rpc("push_allowed", { p_user: user, p_topic: topic, p_seconds: seconds });
  return !error && data === true;
}
function inBackground(work) {
  const runtime = globalThis.EdgeRuntime;
  const guarded = work.catch((err) => console.warn("background", err instanceof Error ? err.message : err));
  if (runtime?.waitUntil) runtime.waitUntil(guarded);
}
export {
  apnsPayload,
  inBackground,
  providerToken,
  pushAllowed,
  pushConfigured,
  sendPush
};
