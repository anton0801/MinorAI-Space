// Sign in with Apple server calls: turn the app's authorization code into a refresh token, and
// revoke it when the account is deleted (App Store Review Guideline 5.1.1(v)).
// Needs APPLE_TEAM_ID, APPLE_KEY_ID and APPLE_PRIVATE_KEY (the .p8 contents) as secrets.

export const BUNDLE_ID = "com.minorailifegroup.MinorAI";

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function clientSecret(
  env: { teamID?: string; keyID?: string; privateKey?: string } = {
    teamID: Deno.env.get("APPLE_TEAM_ID"),
    keyID: Deno.env.get("APPLE_KEY_ID"),
    privateKey: Deno.env.get("APPLE_PRIVATE_KEY"),
  },
  now = Math.floor(Date.now() / 1000),
): Promise<string | null> {
  if (!env.teamID || !env.keyID || !env.privateKey) return null;
  // The key may have been saved with "\n" written out instead of line breaks.
  const pem = env.privateKey.replace(/\\n/g, "\n").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const encoder = new TextEncoder();
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: env.keyID })));
  const payload = base64url(encoder.encode(JSON.stringify({
    iss: env.teamID,
    iat: now,
    exp: now + 3600,
    aud: "https://appleid.apple.com",
    sub: BUNDLE_ID,
  })));
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(`${header}.${payload}`)),
  );
  return `${header}.${payload}.${base64url(signature)}`;
}

async function post(path: string, form: Record<string, string>): Promise<Response> {
  return await fetch(`https://appleid.apple.com/auth/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form),
    signal: AbortSignal.timeout(10_000),
  });
}

// Returns the refresh token for an authorization code, or null when Apple keys are not configured.
export async function exchangeCode(code: string): Promise<string | null> {
  const secret = await clientSecret();
  if (!secret) return null;
  const res = await post("token", { client_id: BUNDLE_ID, client_secret: secret, code, grant_type: "authorization_code" });
  if (!res.ok) {
    console.warn("apple token exchange failed", res.status);
    return null;
  }
  const data = await res.json();
  return typeof data.refresh_token === "string" ? data.refresh_token : null;
}

export async function revoke(refreshToken: string): Promise<boolean> {
  const secret = await clientSecret();
  if (!secret) return false;
  const res = await post("revoke", {
    client_id: BUNDLE_ID,
    client_secret: secret,
    token: refreshToken,
    token_type_hint: "refresh_token",
  });
  return res.ok;
}
