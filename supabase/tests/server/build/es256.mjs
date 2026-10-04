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
export {
  appleKey,
  base64url,
  signJWT
};
