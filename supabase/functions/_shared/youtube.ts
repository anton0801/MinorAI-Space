// YouTube source: the transcript (captions) when the video has them, otherwise the title and
// description. Best effort: YouTube changes its page often, so every step degrades gracefully.
import { decodeEntities } from "./net.ts";

export class YouTubeError extends Error {}

export function videoID(url: string): string | null {
  const text = url.trim();
  const patterns = [
    /youtu\.be\/([A-Za-z0-9_-]{11})/,
    /[?&]v=([A-Za-z0-9_-]{11})/,
    /youtube\.com\/(?:shorts|embed|live|v)\/([A-Za-z0-9_-]{11})/,
  ];
  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) return match[1];
  }
  return null;
}

export function isYouTube(url: string): boolean {
  try {
    const parsed = new URL(/^https?:\/\//i.test(url.trim()) ? url.trim() : `https://${url.trim()}`);
    const host = parsed.hostname.toLowerCase().replace(/\.+$/, "");
    return host === "youtu.be" || host === "youtube.com" || host.endsWith(".youtube.com");
  } catch {
    return false;
  }
}

interface CaptionTrack {
  baseUrl: string;
  languageCode?: string;
  kind?: string;
}

export interface VideoText {
  title: string;
  text: string;
  hasTranscript: boolean;
}

export async function fetchVideoText(url: string, fetcher: typeof fetch = fetch): Promise<VideoText> {
  const id = videoID(url);
  if (!id) throw new YouTubeError("bad_video_link");

  const page = await fetcher(`https://www.youtube.com/watch?v=${id}&hl=en`, {
    headers: {
      "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
      "Accept-Language": "en-US,en;q=0.9",
      Cookie: "CONSENT=YES+1",
    },
    signal: AbortSignal.timeout(10_000),
  }).catch(() => {
    throw new YouTubeError("video_unreachable");
  });
  if (!page.ok) throw new YouTubeError("video_unreachable");
  const html = await page.text();

  const title = decodeEntities(
    extractJSONString(html, '"title":{"simpleText":') ??
      html.match(/<meta name="title" content="([^"]*)"/)?.[1] ??
      "YouTube video",
  );
  const description = extractJSONString(html, '"shortDescription":') ?? "";

  // The Android player API returns caption links that work without a browser token;
  // links embedded in the web page are the second choice.
  const apiKey = html.match(/"INNERTUBE_API_KEY":"([^"]+)"/)?.[1];
  const candidates = [pickTrack(await playerCaptionTracks(id, apiKey, fetcher)), pickTrack(extractCaptionTracks(html))];
  for (const track of candidates) {
    if (!track) continue;
    const transcript = await fetchTranscript(track.baseUrl, fetcher);
    if (transcript.length > 200) return { title, text: `${title}\n\n${transcript}`, hasTranscript: true };
  }
  if (description.length > 200) {
    return { title, text: `${title}\n\n${description}`, hasTranscript: false };
  }
  throw new YouTubeError("youtube_no_transcript");
}

export function extractCaptionTracks(html: string): CaptionTrack[] {
  const start = html.indexOf('"captionTracks":');
  if (start === -1) return [];
  const arrayStart = html.indexOf("[", start);
  const end = matchingBracket(html, arrayStart);
  if (arrayStart === -1 || end === -1) return [];
  try {
    const tracks = JSON.parse(html.slice(arrayStart, end + 1)) as CaptionTrack[];
    return tracks.filter((t) => typeof t.baseUrl === "string");
  } catch {
    return [];
  }
}

// Prefer human captions in English, then any human captions, then auto-generated ones.
export function pickTrack(tracks: CaptionTrack[]): CaptionTrack | null {
  const human = tracks.filter((t) => t.kind !== "asr");
  return human.find((t) => t.languageCode?.startsWith("en")) ?? human[0] ?? tracks[0] ?? null;
}

async function playerCaptionTracks(id: string, apiKey: string | undefined, fetcher: typeof fetch): Promise<CaptionTrack[]> {
  if (!apiKey) return [];
  const response = await fetcher(`https://www.youtube.com/youtubei/v1/player?key=${apiKey}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "User-Agent": "com.google.android.youtube/20.10.38 (Linux; U; Android 14)",
    },
    body: JSON.stringify({
      context: { client: { clientName: "ANDROID", clientVersion: "20.10.38", androidSdkVersion: 34, hl: "en" } },
      videoId: id,
    }),
    signal: AbortSignal.timeout(10_000),
  }).catch(() => null);
  if (!response?.ok) return [];
  const data = await response.json().catch(() => null) as
    | { captions?: { playerCaptionsTracklistRenderer?: { captionTracks?: CaptionTrack[] } } }
    | null;
  return (data?.captions?.playerCaptionsTracklistRenderer?.captionTracks ?? []).filter((t) => typeof t.baseUrl === "string");
}

async function fetchTranscript(baseUrl: string, fetcher: typeof fetch): Promise<string> {
  const url = baseUrl.replace(/\\u0026/g, "&").replace("&fmt=srv3", "");
  // Captions must come from YouTube itself.
  try {
    const host = new URL(url).hostname;
    if (host !== "www.youtube.com" && host !== "youtube.com" && !host.endsWith(".youtube.com")) return "";
  } catch {
    return "";
  }
  const response = await fetcher(url, { signal: AbortSignal.timeout(10_000) }).catch(() => null);
  if (!response?.ok) return "";
  return transcriptFromXML(await response.text());
}

export function transcriptFromXML(xml: string): string {
  const lines: string[] = [];
  for (const match of xml.matchAll(/<text[^>]*>([\s\S]*?)<\/text>/g)) {
    const line = decodeEntities(match[1].replace(/<[^>]+>/g, "")).replace(/\s+/g, " ").trim();
    if (line) lines.push(line);
  }
  return lines.join(" ");
}

function extractJSONString(html: string, marker: string): string | null {
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

function matchingBracket(text: string, open: number): number {
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
