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

// ../../functions/_shared/pushText.ts
function isRussian(language) {
  return language.toLowerCase().startsWith("ru");
}
function ruDays(n) {
  const tens = n % 100;
  const ones = n % 10;
  const word = tens >= 11 && tens <= 14 ? "\u0434\u043D\u0435\u0439" : ones === 1 ? "\u0434\u0435\u043D\u044C" : ones >= 2 && ones <= 4 ? "\u0434\u043D\u044F" : "\u0434\u043D\u0435\u0439";
  return `${n} ${word}`;
}
function enDays(n) {
  return n === 1 ? "1 day" : `${n} days`;
}
var PUSH = {
  collabChanged: (map) => (language) => isRussian(language) ? { title: map, body: "\u0421\u043E\u0430\u0432\u0442\u043E\u0440 \u0432\u043D\u0451\u0441 \u0438\u0437\u043C\u0435\u043D\u0435\u043D\u0438\u044F \u0432 \u043A\u0430\u0440\u0442\u0443." } : { title: map, body: "A collaborator made changes to this map." },
  collabJoined: (map) => (language) => isRussian(language) ? { title: map, body: "\u041A \u0432\u0430\u0448\u0435\u0439 \u043A\u0430\u0440\u0442\u0435 \u043F\u0440\u0438\u0441\u043E\u0435\u0434\u0438\u043D\u0438\u043B\u0441\u044F \u043D\u043E\u0432\u044B\u0439 \u0443\u0447\u0430\u0441\u0442\u043D\u0438\u043A." } : { title: map, body: "Someone new joined your shared map." },
  roleChanged: (map, role) => (language) => isRussian(language) ? { title: map, body: role === "editor" ? "\u0422\u0435\u043F\u0435\u0440\u044C \u0432\u044B \u043C\u043E\u0436\u0435\u0442\u0435 \u0440\u0435\u0434\u0430\u043A\u0442\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u044D\u0442\u0443 \u043A\u0430\u0440\u0442\u0443." : "\u0422\u0435\u043F\u0435\u0440\u044C \u0432\u044B \u043C\u043E\u0436\u0435\u0442\u0435 \u0442\u043E\u043B\u044C\u043A\u043E \u043F\u0440\u043E\u0441\u043C\u0430\u0442\u0440\u0438\u0432\u0430\u0442\u044C \u044D\u0442\u0443 \u043A\u0430\u0440\u0442\u0443." } : { title: map, body: role === "editor" ? "You can now edit this map." : "You can now only view this map." },
  friendJoined: (days, waiting) => (language) => isRussian(language) ? {
    title: "\u0412\u0430\u0448 \u0434\u0440\u0443\u0433 \u043D\u0430\u0447\u0430\u043B \u043F\u043E\u043B\u044C\u0437\u043E\u0432\u0430\u0442\u044C\u0441\u044F Minor AI",
    body: waiting ? `+${ruDays(days)} Minor Plus \u0441\u043E\u0445\u0440\u0430\u043D\u0435\u043D\u044B \u0438 \u0432\u043A\u043B\u044E\u0447\u0430\u0442\u0441\u044F, \u043A\u043E\u0433\u0434\u0430 \u0437\u0430\u043A\u043E\u043D\u0447\u0438\u0442\u0441\u044F \u0432\u0430\u0448\u0430 \u043F\u043E\u0434\u043F\u0438\u0441\u043A\u0430.` : `\u0412\u0430\u043C +${ruDays(days)} Minor Plus. \u0421\u043F\u0430\u0441\u0438\u0431\u043E \u0437\u0430 \u043F\u0440\u0438\u0433\u043B\u0430\u0448\u0435\u043D\u0438\u0435!`
  } : {
    title: "Your friend started using Minor AI",
    body: waiting ? `+${enDays(days)} of Minor Plus are saved and start when your subscription ends.` : `You got ${enDays(days)} of Minor Plus. Thanks for inviting!`
  },
  friendSubscribed: (percent) => (language) => isRussian(language) ? { title: "\u0412\u0430\u0448 \u0434\u0440\u0443\u0433 \u043E\u0444\u043E\u0440\u043C\u0438\u043B \u043F\u043E\u0434\u043F\u0438\u0441\u043A\u0443", body: `\u0412\u0430\u043C \u0441\u043A\u0438\u0434\u043A\u0430 ${percent}% \u043D\u0430 \u043B\u044E\u0431\u0443\u044E \u043F\u043E\u0434\u043F\u0438\u0441\u043A\u0443 Minor. \u0417\u0430\u0431\u0435\u0440\u0438\u0442\u0435 \u0435\u0451 \u0432 \xAB\u041F\u0440\u0438\u0433\u043B\u0430\u0441\u0438\u0442\u044C \u0434\u0440\u0443\u0437\u0435\u0439\xBB.` } : { title: "Your friend subscribed", body: `You get ${percent}% off any Minor subscription. Claim it in Invite Friends.` },
  allowance: (percent) => (language) => isRussian(language) ? { title: `\u0418\u0441\u043F\u043E\u043B\u044C\u0437\u043E\u0432\u0430\u043D\u043E ${percent}% \u043B\u0438\u043C\u0438\u0442\u0430 \u0418\u0418`, body: "\u041B\u0438\u043C\u0438\u0442 \u043E\u0431\u043D\u043E\u0432\u0438\u0442\u0441\u044F 1-\u0433\u043E \u0447\u0438\u0441\u043B\u0430. \u041F\u043E\u0434\u0440\u043E\u0431\u043D\u043E\u0441\u0442\u0438 \u2014 \u0432 \u041D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0430\u0445 \u2192 \u041B\u0438\u043C\u0438\u0442\u044B." } : { title: `${percent}% of your AI allowance used`, body: "It renews on the 1st. See Settings \u2192 Limits for details." },
  test: () => (language) => isRussian(language) ? { title: "Minor AI", body: "\u0423\u0432\u0435\u0434\u043E\u043C\u043B\u0435\u043D\u0438\u044F \u0440\u0430\u0431\u043E\u0442\u0430\u044E\u0442." } : { title: "Minor AI", body: "Notifications are working." }
};

// ../../functions/_shared/referrals.ts
var INVITE_DAYS = { friend: 3, join: 3 };
var INVITE_LIMIT = 3;
var DISCOUNT_PERCENT = 30;
var DISCOUNT_PRODUCTS = [
  "com.minorailifegroup.MinorAI.plusMonthlyPlan",
  "com.minorailifegroup.MinorAI.plusYearlyPlan",
  "com.minorailifegroup.MinorAI.proMonthlyPlan",
  "com.minorailifegroup.MinorAI.proYearlyPlan"
];
function redeemURL(code) {
  return `https://apps.apple.com/redeem?ctx=offercodes&id=6737686540&code=${encodeURIComponent(code)}`;
}
var CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
function newCode(random = (n) => crypto.getRandomValues(new Uint8Array(n))) {
  return Array.from(random(8), (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join("");
}
function cleanCode(raw) {
  const code = String(raw ?? "").toUpperCase().replace(/[\s-]/g, "");
  return /^[A-HJ-NP-Z2-9]{8}$/.test(code) ? code : null;
}
async function rewardJoin(supabase, userId) {
  const { data, error } = await supabase.rpc("reward_referral_join", { p_invitee: userId });
  const reward = data;
  if (error || !reward?.inviter || !reward.days) return;
  await sendPush(supabase, [reward.inviter], "account", {
    text: PUSH.friendJoined(reward.days, reward.waiting === true),
    route: "minorai://invite",
    thread: "invite"
  });
}
function isPaidTransaction(transaction) {
  if (String(transaction.environment ?? "Production") !== "Production") return false;
  if (transaction.offerDiscountType === "FREE_TRIAL") return false;
  if (transaction.price !== void 0 && Number(transaction.price) === 0) return false;
  return true;
}
async function rewardPurchase(supabase, userId, transaction) {
  if (!userId || !isPaidTransaction(transaction)) return;
  const { data, error } = await supabase.rpc("reward_referral_purchase", { p_invitee: userId });
  const reward = data;
  if (error || !reward?.inviter) return;
  await sendPush(supabase, [reward.inviter], "account", {
    text: PUSH.friendSubscribed(DISCOUNT_PERCENT),
    route: "minorai://invite",
    thread: "invite"
  });
}
export {
  CODE_ALPHABET,
  DISCOUNT_PERCENT,
  DISCOUNT_PRODUCTS,
  INVITE_DAYS,
  INVITE_LIMIT,
  cleanCode,
  isPaidTransaction,
  newCode,
  redeemURL,
  rewardJoin,
  rewardPurchase
};
