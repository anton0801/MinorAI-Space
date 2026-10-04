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
async function signJWT(key2, claims) {
  const pem = key2.privateKey.replace(/\\n/g, "\n").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const signer = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const encoder = new TextEncoder();
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: key2.keyID })));
  const payload = base64url(encoder.encode(JSON.stringify(claims)));
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, signer, encoder.encode(`${header}.${payload}`))
  );
  return `${header}.${payload}.${base64url(signature)}`;
}

// ../../functions/_shared/devicecheck.ts
var DeviceCheckError = class extends Error {
};
function key() {
  return appleKey("DEVICECHECK") ?? appleKey("APNS");
}
function deviceCheckConfigured() {
  return key() !== null;
}
async function call(path, token, sandbox, extra = {}) {
  const k = key();
  if (!k) throw new DeviceCheckError("not_configured");
  const jwt = await signJWT(k, { iss: k.teamID, iat: Math.floor(Date.now() / 1e3) });
  const host = sandbox ? "https://api.development.devicecheck.apple.com" : "https://api.devicecheck.apple.com";
  return await fetch(`${host}/v1/${path}`, {
    method: "POST",
    headers: { authorization: `Bearer ${jwt}`, "content-type": "application/json" },
    body: JSON.stringify({ device_token: token, transaction_id: crypto.randomUUID(), timestamp: Date.now(), ...extra }),
    signal: AbortSignal.timeout(1e4)
  });
}
function parseBits(status, text) {
  if (status === 401 || status === 403) throw new DeviceCheckError("key");
  if (status !== 200) throw new DeviceCheckError(`apple_${status}`);
  if (/failed to find bit state/i.test(text)) return false;
  try {
    return JSON.parse(text).bit0 === true;
  } catch {
    throw new DeviceCheckError("bad_reply");
  }
}
async function deviceTaken(token, sandbox) {
  let res = await call("query_two_bits", token, sandbox);
  let text = await res.text();
  if (res.status === 400) {
    res = await call("query_two_bits", token, !sandbox);
    text = await res.text();
    return { taken: parseBits(res.status, text), sandbox: !sandbox };
  }
  return { taken: parseBits(res.status, text), sandbox };
}
async function markDevice(token, sandbox) {
  const res = await call("update_two_bits", token, sandbox, { bit0: true, bit1: false });
  await res.body?.cancel();
  if (res.status !== 200) throw new DeviceCheckError(`apple_${res.status}`);
}
export {
  DeviceCheckError,
  deviceCheckConfigured,
  deviceTaken,
  markDevice,
  parseBits
};
