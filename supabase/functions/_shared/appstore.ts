// Verification of App Store signed data (StoreKit 2 transactions, App Store Server Notifications).
// A JWS from Apple carries its certificate chain in the x5c header: leaf, intermediate, Apple Root
// CA - G3. We check the chain up to the pinned root, Apple's marker extensions, validity dates and
// finally the ES256 signature. Pure WebCrypto, so it runs in Deno (edge) and Node (tests).

const APPLE_ROOT_G3_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";
const OID_LEAF_MARKER = "1.2.840.113635.100.6.11.1"; // App Store receipt signing
const OID_INTERMEDIATE_MARKER = "1.2.840.113635.100.6.2.1"; // Apple WWDR intermediate

export class AppStoreVerificationError extends Error {}

export interface VerifyOptions {
  rootFingerprint?: string; // hex SHA-256 of the trusted root, overridable for tests
  allowXcode?: boolean; // accept local StoreKit testing transactions (no Apple chain)
  now?: Date;
}

export async function verifyAppleJWS(jws: string, options: VerifyOptions = {}): Promise<Record<string, unknown>> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new AppStoreVerificationError("malformed");
  const header = JSON.parse(utf8(base64url(parts[0]))) as { alg?: string; x5c?: string[] };
  const payload = JSON.parse(utf8(base64url(parts[1]))) as Record<string, unknown>;

  if (payload.environment === "Xcode") {
    if (options.allowXcode) return payload;
    throw new AppStoreVerificationError("xcode_not_allowed");
  }
  if (header.alg !== "ES256" || !Array.isArray(header.x5c) || header.x5c.length !== 3) {
    throw new AppStoreVerificationError("bad_header");
  }

  const ders = header.x5c.map((c) => base64(c));
  const [leaf, intermediate, root] = ders.map(parseCertificate);

  const fingerprint = hex(new Uint8Array(await crypto.subtle.digest("SHA-256", ders[2])));
  if (fingerprint !== (options.rootFingerprint ?? APPLE_ROOT_G3_SHA256)) {
    throw new AppStoreVerificationError("untrusted_root");
  }
  if (!leaf.extensions.includes(OID_LEAF_MARKER)) throw new AppStoreVerificationError("leaf_marker");
  if (!intermediate.extensions.includes(OID_INTERMEDIATE_MARKER)) throw new AppStoreVerificationError("intermediate_marker");

  const signedAt = typeof payload.signedDate === "number" ? new Date(payload.signedDate) : (options.now ?? new Date());
  for (const cert of [leaf, intermediate, root]) {
    if (signedAt < cert.notBefore || signedAt > cert.notAfter) throw new AppStoreVerificationError("expired_certificate");
  }

  if (!(await verifyCertificate(intermediate, root))) throw new AppStoreVerificationError("intermediate_signature");
  if (!(await verifyCertificate(leaf, intermediate))) throw new AppStoreVerificationError("leaf_signature");

  const leafKey = await importKey(leaf);
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    leafKey,
    base64url(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!ok) throw new AppStoreVerificationError("signature");
  return payload;
}

// Reads a JWS payload without verifying it (only for data already verified as part of another JWS).
export function decodeJWS(jws: string): Record<string, unknown> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new AppStoreVerificationError("malformed");
  return JSON.parse(utf8(base64url(parts[1])));
}

// ---------- X.509 ----------

interface Certificate {
  tbs: Uint8Array;
  signatureAlgorithm: string;
  signature: Uint8Array;
  spki: Uint8Array;
  curve: string;
  notBefore: Date;
  notAfter: Date;
  extensions: string[];
}

const CURVES: Record<string, { name: string; size: number }> = {
  "1.2.840.10045.3.1.7": { name: "P-256", size: 32 },
  "1.3.132.0.34": { name: "P-384", size: 48 },
};

const HASHES: Record<string, string> = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
};

function parseCertificate(der: Uint8Array): Certificate {
  const cert = readNode(der, 0);
  const [tbs, signatureAlgorithm, signatureValue] = childrenOf(der, cert);
  const fields = childrenOf(der, tbs);
  let i = fields[0].tag === 0xa0 ? 1 : 0; // optional explicit version
  i += 2; // serialNumber, signature algorithm
  i += 1; // issuer
  const validity = childrenOf(der, fields[i++]);
  i += 1; // subject
  const spkiNode = fields[i++];
  const spkiAlgorithm = childrenOf(der, childrenOf(der, spkiNode)[0]);
  const extensions: string[] = [];
  for (const field of fields.slice(i)) {
    if (field.tag !== 0xa3) continue;
    const list = childrenOf(der, childrenOf(der, field)[0]);
    for (const extension of list) extensions.push(oid(der, childrenOf(der, extension)[0]));
  }
  return {
    tbs: der.slice(tbs.start, tbs.end),
    signatureAlgorithm: oid(der, childrenOf(der, signatureAlgorithm)[0]),
    signature: der.slice(signatureValue.start + signatureValue.headerLength + 1, signatureValue.end),
    spki: der.slice(spkiNode.start, spkiNode.end),
    curve: spkiAlgorithm[1] ? oid(der, spkiAlgorithm[1]) : "",
    notBefore: time(der, validity[0]),
    notAfter: time(der, validity[1]),
    extensions,
  };
}

async function importKey(cert: Certificate): Promise<CryptoKey> {
  const curve = CURVES[cert.curve];
  if (!curve) throw new AppStoreVerificationError("unsupported_curve");
  return await crypto.subtle.importKey("spki", cert.spki, { name: "ECDSA", namedCurve: curve.name }, false, ["verify"]);
}

async function verifyCertificate(cert: Certificate, issuer: Certificate): Promise<boolean> {
  const hash = HASHES[cert.signatureAlgorithm];
  const curve = CURVES[issuer.curve];
  if (!hash || !curve) return false;
  const key = await importKey(issuer);
  return await crypto.subtle.verify({ name: "ECDSA", hash }, key, derSignatureToRaw(cert.signature, curve.size), cert.tbs);
}

// ECDSA signatures inside certificates are DER SEQUENCE { r, s }; WebCrypto wants r || s.
function derSignatureToRaw(der: Uint8Array, size: number): Uint8Array {
  const sequence = readNode(der, 0);
  const [r, s] = childrenOf(der, sequence);
  const out = new Uint8Array(size * 2);
  for (const [index, node] of [r, s].entries()) {
    let bytes = der.slice(node.start + node.headerLength, node.end);
    while (bytes.length > size && bytes[0] === 0) bytes = bytes.slice(1);
    if (bytes.length > size) throw new AppStoreVerificationError("bad_signature_encoding");
    out.set(bytes, index * size + (size - bytes.length));
  }
  return out;
}

// ---------- DER ----------

interface DERNode {
  tag: number;
  start: number;
  headerLength: number;
  end: number;
}

function readNode(buf: Uint8Array, pos: number): DERNode {
  if (pos + 2 > buf.length) throw new AppStoreVerificationError("truncated");
  const tag = buf[pos];
  let length = buf[pos + 1];
  let headerLength = 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 4) throw new AppStoreVerificationError("bad_length");
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + buf[pos + 2 + i];
    headerLength = 2 + count;
  }
  const end = pos + headerLength + length;
  if (end > buf.length) throw new AppStoreVerificationError("truncated");
  return { tag, start: pos, headerLength, end };
}

function childrenOf(buf: Uint8Array, node: DERNode): DERNode[] {
  const out: DERNode[] = [];
  let pos = node.start + node.headerLength;
  while (pos < node.end) {
    const child = readNode(buf, pos);
    out.push(child);
    pos = child.end;
  }
  return out;
}

function oid(buf: Uint8Array, node: DERNode): string {
  const bytes = buf.slice(node.start + node.headerLength, node.end);
  const parts: number[] = [Math.floor(bytes[0] / 40), bytes[0] % 40];
  let value = 0;
  for (const byte of bytes.slice(1)) {
    value = value * 128 + (byte & 0x7f);
    if (!(byte & 0x80)) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

function time(buf: Uint8Array, node: DERNode): Date {
  const text = utf8(buf.slice(node.start + node.headerLength, node.end));
  // UTCTime YYMMDDHHMMSSZ or GeneralizedTime YYYYMMDDHHMMSSZ
  const full = node.tag === 0x17 ? (Number(text.slice(0, 2)) >= 50 ? "19" : "20") + text : text;
  const iso = `${full.slice(0, 4)}-${full.slice(4, 6)}-${full.slice(6, 8)}T${full.slice(8, 10)}:${full.slice(10, 12)}:${full.slice(12, 14)}Z`;
  return new Date(iso);
}

// ---------- encoding ----------

function base64(text: string): Uint8Array {
  const binary = atob(text);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

function base64url(text: string): Uint8Array {
  const normal = text.replace(/-/g, "+").replace(/_/g, "/");
  return base64(normal + "=".repeat((4 - (normal.length % 4)) % 4));
}

function utf8(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}
