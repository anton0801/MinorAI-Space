// ../../functions/_shared/sources.ts
var SEGMENT_ID = /^s[1-9]\d{0,5}$/;
var MAX_SEGMENTS = 4e3;
var MAX_SEGMENT_CHARS = 2e3;
function cleanSegments(raw) {
  if (!Array.isArray(raw)) return [];
  const seen = /* @__PURE__ */ new Set();
  const out = [];
  for (const item of raw.slice(0, MAX_SEGMENTS)) {
    const id = String(item?.id ?? "");
    const text = String(item?.text ?? "").replace(/\s+/g, " ").trim().slice(0, MAX_SEGMENT_CHARS);
    if (!SEGMENT_ID.test(id) || seen.has(id) || !text) continue;
    seen.add(id);
    out.push({ id, text });
  }
  return out;
}
function cutSegments(text, size = 500) {
  const clean = text.replace(/\s+/g, " ").trim();
  if (!clean) return [];
  const sentences = clean.match(/[^.!?…]+(?:[.!?…]+|$)\s*/g) ?? [clean];
  const out = [];
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
function timedSegments(cues, span = 20) {
  const out = [];
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
function round(seconds) {
  return Math.round(seconds * 10) / 10;
}
function markedText(segments, cap) {
  const used = [];
  const lines = [];
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
var SOURCE_RULE = `The material is split into passages; each starts with its id in brackets, like [s12]. On every idea you add, set "src" to the ids of the 1 to 3 passages that state it directly, for example "src": ["s12"]. Use only ids that appear in the material. When no passage states an idea directly, leave "src" out; never guess an id.`;
function cleanSrc(raw) {
  if (!Array.isArray(raw)) return void 0;
  const ids = [...new Set(raw.filter((id) => typeof id === "string" && SEGMENT_ID.test(id)))].slice(0, 6);
  return ids.length ? ids : void 0;
}
export {
  SEGMENT_ID,
  SOURCE_RULE,
  cleanSegments,
  cleanSrc,
  cutSegments,
  markedText,
  timedSegments
};
