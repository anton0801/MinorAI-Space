import fs from "node:fs";
import crypto from "node:crypto";
import { verifyAppleJWS, AppStoreVerificationError } from "./build/appstore.mjs";

const b64u = (b) => Buffer.from(b).toString("base64url");
const der = (n) => fs.readFileSync(`${n}.der`);
const rootFp = crypto.createHash("sha256").update(der("root")).digest("hex");
const leafKey = crypto.createPrivateKey(fs.readFileSync("leaf.p8"));
const intKey = crypto.createPrivateKey(fs.readFileSync("int.key"));

function jws(payload, { leaf = "leaf", key = leafKey, chain } = {}) {
  const header = { alg: "ES256", x5c: (chain ?? [leaf, "int", "root"]).map((n) => der(n).toString("base64")) };
  const signingInput = `${b64u(JSON.stringify(header))}.${b64u(JSON.stringify(payload))}`;
  const sig = crypto.sign("sha256", Buffer.from(signingInput), { key, dsaEncoding: "ieee-p1363" });
  return `${signingInput}.${b64u(sig)}`;
}

const base = { bundleId: "com.minorailifegroup.MinorAI", productId: "com.minorailifegroup.MinorAI.plusMonthlyPlan", environment: "Sandbox", signedDate: Date.now() };
let pass = 0, fail = 0;
async function expect(name, promise, wantError) {
  try {
    const out = await promise;
    if (wantError) { fail++; console.log("FAIL", name, "expected", wantError, "got payload"); }
    else { pass++; console.log("ok  ", name, out.productId); }
  } catch (e) {
    const code = e instanceof AppStoreVerificationError ? e.message : `${e.name}:${e.message}`;
    if (wantError && code === wantError) { pass++; console.log("ok  ", name, "->", code); }
    else { fail++; console.log("FAIL", name, "got", code, "want", wantError ?? "success"); }
  }
}
const opts = { rootFingerprint: rootFp };
await expect("valid chain + signature", verifyAppleJWS(jws(base), opts));
const good = jws(base); const [h, p, s] = good.split(".");
const forged = `${h}.${b64u(JSON.stringify({ ...base, productId: "com.minorailifegroup.MinorAI.proYearlyPlan" }))}.${s}`;
await expect("tampered payload", verifyAppleJWS(forged, opts), "signature");
await expect("real Apple root pinned (test root rejected)", verifyAppleJWS(jws(base)), "untrusted_root");
await expect("leaf without Apple marker", verifyAppleJWS(jws(base, { leaf: "leaf_nomarker" }), opts), "leaf_marker");
await expect("signed by wrong key", verifyAppleJWS(jws(base, { key: intKey }), opts), "signature");
await expect("chain order swapped", verifyAppleJWS(jws(base, { chain: ["int", "leaf", "root"] }), opts), "leaf_marker");
await expect("Xcode env rejected by default", verifyAppleJWS(jws({ ...base, environment: "Xcode" }), opts), "xcode_not_allowed");
await expect("Xcode env allowed when enabled", verifyAppleJWS(jws({ ...base, environment: "Xcode" }), { ...opts, allowXcode: true }));
await expect("signed before cert validity", verifyAppleJWS(jws({ ...base, signedDate: Date.UTC(2001, 0, 1) }), opts), "expired_certificate");
await expect("garbage", verifyAppleJWS("a.b", opts), "malformed");
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
