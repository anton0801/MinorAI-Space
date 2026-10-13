// Passages of a material the AI can point to. The app sends them for what it read itself
// (documents, scans, voice, pasted text); the server cuts them from what it fetched (web pages,
// video captions) and sends them back, so the app keeps exactly what the AI saw. A new idea may
// name the passages that state it ("src"); the app checks the ids against its own copy and takes
// quotes only from there, never from the AI.

export interface Segment {
  id: string;
  text: string;
  start?: number; // seconds into a video, for caption passages
  end?: number;
}

export interface Cue {
  start: number;
  dur: number;
  text: string;
}

export const SEGMENT_ID = /^s[1-9]\d{0,5}$/;
const MAX_SEGMENTS = 4000;
const MAX_SEGMENT_CHARS = 2000;

// Passages sent by the app: ids "s1", "s2"…, each once, with text; anything else is left out.
export function cleanSegments(raw: unknown): Segment[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<string>();
  const out: Segment[] = [];
  for (const item of raw.slice(0, MAX_SEGMENTS)) {
    const id = String((item as Segment)?.id ?? "");
    const text = String((item as Segment)?.text ?? "").replace(/\s+/g, " ").trim().slice(0, MAX_SEGMENT_CHARS);
    if (!SEGMENT_ID.test(id) || seen.has(id) || !text) continue;
    seen.add(id);
    out.push({ id, text });
  }
  return out;
}

// Fetched text cut at sentence ends into passages of about `size` characters (a very long
// sentence is cut on its own).
export function cutSegments(text: string, size = 500): Segment[] {
  const clean = text.replace(/\s+/g, " ").trim();
  if (!clean) return [];
  const sentences = clean.match(/[^.!?…]+(?:[.!?…]+|$)\s*/g) ?? [clean];
  const out: Segment[] = [];
  let current = "";
  const push = () => {
    const piece = current.trim();
    if (piece) out.push({ id: `s${out.length + 1}`, text: piece });
    current = "";
  };
  for (const sentence of sentences) {
    if (sentence.length > size * 2) {
      push();
      for (let i = 0; i < sentence.length; i += size) {
        current = sentence.slice(i, i + size);
        push();
      }
      continue;
    }
    if (current.length + sentence.length > size && current.length > 0) push();
    current += sentence;
  }
  push();
  return out.slice(0, MAX_SEGMENTS);
}

// Caption cues joined into passages of about `span` seconds, with the time they start and end.
export function timedSegments(cues: Cue[], span = 20): Segment[] {
  const out: Segment[] = [];
  let text = "";
  let start = -1;
  let end = 0;
  const push = () => {
    const piece = text.trim();
    if (piece && start >= 0) out.push({ id: `s${out.length + 1}`, text: piece, start: round(start), end: round(end) });
    text = "";
    start = -1;
  };
  for (const cue of cues) {
    if (!Number.isFinite(cue.start) || cue.start < 0 || !cue.text) continue;
    if (start < 0) start = cue.start;
    text += (text ? " " : "") + cue.text;
    end = Math.max(end, cue.start + (Number.isFinite(cue.dur) && cue.dur > 0 ? cue.dur : 0));
    if (end - start >= span) push();
  }
  push();
  return out.slice(0, MAX_SEGMENTS);
}

function round(seconds: number): number {
  return Math.round(seconds * 10) / 10;
}

// The material for the AI, each passage after its id in brackets, up to `cap` characters.
export function markedText(segments: Segment[], cap: number): { text: string; used: Segment[]; truncated: boolean } {
  const used: Segment[] = [];
  const lines: string[] = [];
  let length = 0;
  for (const segment of segments) {
    const line = `[${segment.id}] ${segment.text}`;
    if (length + line.length + 1 > cap && used.length > 0) break;
    lines.push(line);
    used.push(segment);
    length += line.length + 1;
  }
  return { text: lines.join("\n"), used, truncated: used.length < segments.length };
}

export const SOURCE_RULE = `The material is split into passages; each starts with its id in brackets, like [s12]. On every idea you add, set "src" to the ids of the 1 to 3 passages that state it directly, for example "src": ["s12"]. Use only ids that appear in the material. When no passage states an idea directly, leave "src" out; never guess an id.`;

// The passage ids an idea points to: well formed, at most 6, each once.
export function cleanSrc(raw: unknown): string[] | undefined {
  if (!Array.isArray(raw)) return undefined;
  const ids = [...new Set(raw.filter((id): id is string => typeof id === "string" && SEGMENT_ID.test(id)))].slice(0, 6);
  return ids.length ? ids : undefined;
}
