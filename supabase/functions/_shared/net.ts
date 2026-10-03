// Fetching user-supplied links without turning the server into a proxy into private networks.
// Every hop (including redirects) must be http(s) on port 80/443 to a public address, the host
// is resolved and checked, and the body is read with a hard byte cap.

export class NetError extends Error {}

const MAX_REDIRECTS = 3;

type Resolver = (host: string) => Promise<string[]>;

export function isPrivateAddress(address: string): boolean {
  const ip = address.toLowerCase().replace(/^\[|\]$/g, "");
  if (ip.includes(":")) {
    if (ip === "::" || ip === "::1") return true;
    if (/^(fc|fd)/.test(ip)) return true; // unique local
    if (/^fe[89ab]/.test(ip)) return true; // link local
    const mapped = ip.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
    if (mapped) return isPrivateAddress(mapped[1]);
    const mappedHex = ip.match(/^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/);
    if (mappedHex) {
      const hi = parseInt(mappedHex[1], 16);
      const lo = parseInt(mappedHex[2], 16);
      return isPrivateAddress(`${hi >> 8}.${hi & 255}.${lo >> 8}.${lo & 255}`);
    }
    // Anything else counts as public only inside 2000::/3 (global unicast), minus special ranges.
    if (!/^[23][0-9a-f]{0,3}:/.test(ip)) return true;
    if (/^(2001:db8|2001:0db8|2002:|2001:0?:|2001::)/.test(ip)) return true; // documentation, 6to4, Teredo
    return false;
  }
  const parts = ip.split(".").map(Number);
  if (parts.length !== 4 || parts.some((p) => !Number.isInteger(p) || p < 0 || p > 255)) return true;
  const [a, b] = parts;
  return a === 0 || a === 10 || a === 127 || a >= 224 ||
    (a === 100 && b >= 64 && b <= 127) || // carrier-grade NAT
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) ||
    (a === 192 && b === 0) ||
    (a === 198 && (b === 18 || b === 19)) ||
    (a === 198 && b === 51) || (a === 203 && b === 0);
}

export function checkURL(raw: string): URL {
  let url: URL;
  try {
    url = new URL(/^https?:\/\//i.test(raw) ? raw : `https://${raw}`);
  } catch {
    throw new NetError("bad_link");
  }
  if (!/^https?:$/.test(url.protocol)) throw new NetError("bad_link");
  if (url.username || url.password) throw new NetError("bad_link");
  if (url.port && url.port !== "80" && url.port !== "443") throw new NetError("bad_link");
  url.hostname = url.hostname.replace(/\.+$/, "");
  const host = url.hostname.toLowerCase();
  if (!host || host === "localhost" || host.endsWith(".localhost") || host.endsWith(".local") ||
    host.endsWith(".internal") || host.endsWith(".lan") || !host.includes(".")) {
    throw new NetError("bad_link");
  }
  return url;
}

async function defaultResolver(host: string): Promise<string[]> {
  const results: string[] = [];
  for (const type of ["A", "AAAA"] as const) {
    try {
      results.push(...(await Deno.resolveDns(host, type)));
    } catch {
      // no records of this type
    }
  }
  return results;
}

async function assertPublic(url: URL, resolve: Resolver) {
  const host = url.hostname.replace(/^\[|\]$/g, "");
  const literal = /^[\d.]+$/.test(host) || host.includes(":");
  const addresses = literal ? [host] : await resolve(host);
  if (addresses.length === 0) throw new NetError("link_unreachable");
  if (addresses.some(isPrivateAddress)) throw new NetError("bad_link");
}

// Fetches a public page and returns at most `maxBytes` of its body as text.
export async function fetchPublicText(
  raw: string,
  options: { maxBytes?: number; timeoutMs?: number; resolve?: Resolver; fetcher?: typeof fetch } = {},
): Promise<{ text: string; contentType: string; url: URL }> {
  const maxBytes = options.maxBytes ?? 2_000_000;
  const resolve = options.resolve ?? defaultResolver;
  const fetcher = options.fetcher ?? fetch;
  const signal = AbortSignal.timeout(options.timeoutMs ?? 10_000);

  let url = checkURL(raw);
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    await assertPublic(url, resolve);
    const response = await fetcher(url, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; MinorBot/1.0)", Accept: "text/html,text/plain;q=0.9" },
      redirect: "manual",
      signal,
    }).catch(() => {
      throw new NetError("link_unreachable");
    });
    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get("location");
      await response.body?.cancel();
      if (!location) throw new NetError("link_unreachable");
      url = checkURL(new URL(location, url).toString());
      continue;
    }
    if (!response.ok || !response.body) throw new NetError("link_unreachable");
    const contentType = response.headers.get("content-type") ?? "";
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (size < maxBytes) {
      const { value, done } = await reader.read();
      if (done) break;
      chunks.push(value);
      size += value.length;
    }
    await reader.cancel().catch(() => {});
    const bytes = new Uint8Array(Math.min(size, maxBytes));
    let offset = 0;
    for (const chunk of chunks) {
      const part = chunk.subarray(0, Math.min(chunk.length, bytes.length - offset));
      bytes.set(part, offset);
      offset += part.length;
      if (offset >= bytes.length) break;
    }
    return { text: new TextDecoder().decode(bytes), contentType, url };
  }
  throw new NetError("link_unreachable");
}

// Visible text of an HTML document in one linear pass (skips script, style, nav and footer).
export function htmlToText(html: string): string {
  const skip = new Set(["script", "style", "noscript", "nav", "footer", "svg", "template"]);
  let out = "";
  let i = 0;
  let skipping: string | null = null;
  while (i < html.length) {
    const lt = html.indexOf("<", i);
    if (lt === -1) {
      if (!skipping) out += html.slice(i);
      break;
    }
    if (!skipping) out += html.slice(i, lt) + " ";
    const gt = html.indexOf(">", lt + 1);
    if (gt === -1) break;
    const tag = html.slice(lt + 1, gt);
    const name = tag.replace(/^\//, "").split(/[\s/]/, 1)[0].toLowerCase();
    if (skipping) {
      if (tag.startsWith("/") && name === skipping) skipping = null;
    } else if (!tag.startsWith("/") && skip.has(name) && !tag.endsWith("/")) {
      skipping = name;
    }
    i = gt + 1;
  }
  return decodeEntities(out).replace(/\s+/g, " ").trim();
}

export function decodeEntities(text: string): string {
  return text.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos|nbsp|#39);/gi, (entity, body: string) => {
    const key = body.toLowerCase();
    if (key.startsWith("#x") || key.startsWith("#")) {
      const code = key.startsWith("#x") ? parseInt(key.slice(2), 16) : parseInt(key.slice(1), 10);
      return Number.isFinite(code) && code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : "";
    }
    return ({ amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " } as Record<string, string>)[key] ?? entity;
  });
}
