// ../../functions/_shared/net.ts
function decodeEntities(text) {
  return text.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos|nbsp|#39);/gi, (entity, body) => {
    const key = body.toLowerCase();
    if (key.startsWith("#x") || key.startsWith("#")) {
      const code = key.startsWith("#x") ? parseInt(key.slice(2), 16) : parseInt(key.slice(1), 10);
      return Number.isFinite(code) && code > 0 && code <= 1114111 ? String.fromCodePoint(code) : "";
    }
    return { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " }[key] ?? entity;
  });
}

// ../../functions/_shared/youtube.ts
var YouTubeError = class extends Error {
};
function videoID(url) {
  const text = url.trim();
  const patterns = [
    /youtu\.be\/([A-Za-z0-9_-]{11})/,
    /[?&]v=([A-Za-z0-9_-]{11})/,
    /youtube\.com\/(?:shorts|embed|live|v)\/([A-Za-z0-9_-]{11})/
  ];
  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) return match[1];
  }
  return null;
}
function isYouTube(url) {
  try {
    const parsed = new URL(/^https?:\/\//i.test(url.trim()) ? url.trim() : `https://${url.trim()}`);
    const host = parsed.hostname.toLowerCase().replace(/\.+$/, "");
    return host === "youtu.be" || host === "youtube.com" || host.endsWith(".youtube.com");
  } catch {
    return false;
  }
}
async function fetchVideoText(url, fetcher = fetch) {
  const id = videoID(url);
  if (!id) throw new YouTubeError("bad_video_link");
  const page = await fetcher(`https://www.youtube.com/watch?v=${id}&hl=en`, {
    headers: {
      "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
      "Accept-Language": "en-US,en;q=0.9",
      Cookie: "CONSENT=YES+1"
    },
    signal: AbortSignal.timeout(1e4)
  }).catch(() => {
    throw new YouTubeError("video_unreachable");
  });
  if (!page.ok) throw new YouTubeError("video_unreachable");
  const html = await page.text();
  const title = decodeEntities(
    extractJSONString(html, '"title":{"simpleText":') ?? html.match(/<meta name="title" content="([^"]*)"/)?.[1] ?? "YouTube video"
  );
  const description = extractJSONString(html, '"shortDescription":') ?? "";
  const apiKey = html.match(/"INNERTUBE_API_KEY":"([^"]+)"/)?.[1];
  const candidates = [pickTrack(await playerCaptionTracks(id, apiKey, fetcher)), pickTrack(extractCaptionTracks(html))];
  for (const track of candidates) {
    if (!track) continue;
    const transcript = await fetchTranscript(track.baseUrl, fetcher);
    if (transcript.length > 200) return { title, text: `${title}

${transcript}`, hasTranscript: true };
  }
  if (description.length > 200) {
    return { title, text: `${title}

${description}`, hasTranscript: false };
  }
  throw new YouTubeError("youtube_no_transcript");
}
function extractCaptionTracks(html) {
  const start = html.indexOf('"captionTracks":');
  if (start === -1) return [];
  const arrayStart = html.indexOf("[", start);
  const end = matchingBracket(html, arrayStart);
  if (arrayStart === -1 || end === -1) return [];
  try {
    const tracks = JSON.parse(html.slice(arrayStart, end + 1));
    return tracks.filter((t) => typeof t.baseUrl === "string");
  } catch {
    return [];
  }
}
function pickTrack(tracks) {
  const human = tracks.filter((t) => t.kind !== "asr");
  return human.find((t) => t.languageCode?.startsWith("en")) ?? human[0] ?? tracks[0] ?? null;
}
async function playerCaptionTracks(id, apiKey, fetcher) {
  if (!apiKey) return [];
  const response = await fetcher(`https://www.youtube.com/youtubei/v1/player?key=${apiKey}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "User-Agent": "com.google.android.youtube/20.10.38 (Linux; U; Android 14)"
    },
    body: JSON.stringify({
      context: { client: { clientName: "ANDROID", clientVersion: "20.10.38", androidSdkVersion: 34, hl: "en" } },
      videoId: id
    }),
    signal: AbortSignal.timeout(1e4)
  }).catch(() => null);
  if (!response?.ok) return [];
  const data = await response.json().catch(() => null);
  return (data?.captions?.playerCaptionsTracklistRenderer?.captionTracks ?? []).filter((t) => typeof t.baseUrl === "string");
}
async function fetchTranscript(baseUrl, fetcher) {
  const url = baseUrl.replace(/\\u0026/g, "&").replace("&fmt=srv3", "");
  try {
    const host = new URL(url).hostname;
    if (host !== "www.youtube.com" && host !== "youtube.com" && !host.endsWith(".youtube.com")) return "";
  } catch {
    return "";
  }
  const response = await fetcher(url, { signal: AbortSignal.timeout(1e4) }).catch(() => null);
  if (!response?.ok) return "";
  return transcriptFromXML(await response.text());
}
function transcriptFromXML(xml) {
  const lines = [];
  for (const match of xml.matchAll(/<text[^>]*>([\s\S]*?)<\/text>/g)) {
    const line = decodeEntities(match[1].replace(/<[^>]+>/g, "")).replace(/\s+/g, " ").trim();
    if (line) lines.push(line);
  }
  return lines.join(" ");
}
function extractJSONString(html, marker) {
  const at = html.indexOf(marker);
  if (at === -1) return null;
  const quote = html.indexOf('"', at + marker.length);
  if (quote === -1) return null;
  let i = quote + 1;
  let raw = "";
  while (i < html.length) {
    const c = html[i];
    if (c === "\\") {
      raw += c + html[i + 1];
      i += 2;
      continue;
    }
    if (c === '"') break;
    raw += c;
    i++;
  }
  try {
    return JSON.parse(`"${raw}"`);
  } catch {
    return null;
  }
}
function matchingBracket(text, open) {
  if (open < 0) return -1;
  let depth = 0;
  let inString = false;
  for (let i = open; i < text.length; i++) {
    const c = text[i];
    if (inString) {
      if (c === "\\") i++;
      else if (c === '"') inString = false;
      continue;
    }
    if (c === '"') inString = true;
    else if (c === "[") depth++;
    else if (c === "]" && --depth === 0) return i;
  }
  return -1;
}
export {
  YouTubeError,
  extractCaptionTracks,
  fetchVideoText,
  isYouTube,
  pickTrack,
  transcriptFromXML,
  videoID
};
