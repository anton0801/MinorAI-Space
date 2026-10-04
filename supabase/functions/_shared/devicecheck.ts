// Apple DeviceCheck: two bits Apple keeps for each device and developer, kept when the app is
// deleted and installed again. Bit 0 means "this iPhone already took an invitation", so one
// device can't collect invitation rewards with account after account.
// Uses DEVICECHECK_KEY_ID / DEVICECHECK_PRIVATE_KEY, or the APNs key when DeviceCheck is ticked on it.
import { appleKey, signJWT } from "./es256.ts";

export class DeviceCheckError extends Error {}

function key() {
  return appleKey("DEVICECHECK") ?? appleKey("APNS");
}

export function deviceCheckConfigured(): boolean {
  return key() !== null;
}

async function call(path: "query_two_bits" | "update_two_bits", token: string, sandbox: boolean, extra: Record<string, unknown> = {}) {
  const k = key();
  if (!k) throw new DeviceCheckError("not_configured");
  const jwt = await signJWT(k, { iss: k.teamID, iat: Math.floor(Date.now() / 1000) });
  const host = sandbox ? "https://api.development.devicecheck.apple.com" : "https://api.devicecheck.apple.com";
  return await fetch(`${host}/v1/${path}`, {
    method: "POST",
    headers: { authorization: `Bearer ${jwt}`, "content-type": "application/json" },
    body: JSON.stringify({ device_token: token, transaction_id: crypto.randomUUID(), timestamp: Date.now(), ...extra }),
    signal: AbortSignal.timeout(10_000),
  });
}

// Reads Apple's answer: a JSON object with the bits, or text when the device has none yet.
// 401/403 mean the key can't use DeviceCheck (not ticked for it): reported as "key".
export function parseBits(status: number, text: string): boolean {
  if (status === 401 || status === 403) throw new DeviceCheckError("key");
  if (status !== 200) throw new DeviceCheckError(`apple_${status}`);
  if (/failed to find bit state/i.test(text)) return false;
  try {
    return JSON.parse(text).bit0 === true;
  } catch {
    throw new DeviceCheckError("bad_reply");
  }
}

// True when this device already took an invitation. A token from a development build is
// tried against Apple's development server too.
export async function deviceTaken(token: string, sandbox: boolean): Promise<{ taken: boolean; sandbox: boolean }> {
  let res = await call("query_two_bits", token, sandbox);
  let text = await res.text();
  if (res.status === 400) {
    res = await call("query_two_bits", token, !sandbox);
    text = await res.text();
    return { taken: parseBits(res.status, text), sandbox: !sandbox };
  }
  return { taken: parseBits(res.status, text), sandbox };
}

export async function markDevice(token: string, sandbox: boolean): Promise<void> {
  const res = await call("update_two_bits", token, sandbox, { bit0: true, bit1: false });
  await res.body?.cancel();
  if (res.status !== 200) throw new DeviceCheckError(`apple_${res.status}`);
}
