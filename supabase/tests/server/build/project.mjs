// ../../functions/_shared/models.ts
function clip(text, max) {
  const s = String(text ?? "");
  if (s.length <= max) return s;
  let cut = max - 1;
  const last = s.charCodeAt(cut - 1);
  if (last >= 55296 && last <= 56319) cut -= 1;
  return s.slice(0, cut) + "\u2026";
}

// ../../functions/_shared/project.ts
var STEP_LIMIT = 3;
var MEMORY_TEXT = 120;
function key(text) {
  return text.toLowerCase().replace(/[\s.!?…,;:"'«»“”()-]+/g, " ").trim();
}
function line(raw, max) {
  return clip(String(raw ?? "").replace(/\s+/g, " ").trim(), max).replace(/^[-•*\d.)\s]+/, "").trim();
}
function cleanSteps(raw, existing) {
  const list = Array.isArray(raw?.steps) ? raw.steps : [];
  const seen = new Set(existing.map(key));
  const steps = [];
  for (const item of list) {
    const title = line(item?.title, 80);
    if (!title || seen.has(key(title))) continue;
    seen.add(key(title));
    steps.push({ title, detail: line(item?.detail, 100) });
    if (steps.length === STEP_LIMIT) break;
  }
  return steps;
}
function cleanMemory(raw, current) {
  const reply = raw ?? {};
  const known = new Set([...current.decisions ?? [], ...current.questions ?? [], current.goal ?? ""].map(key).filter(Boolean));
  const pick = (value) => {
    const result = [];
    for (const item of Array.isArray(value) ? value : []) {
      const text = line(item, MEMORY_TEXT);
      if (!text || known.has(key(text))) continue;
      known.add(key(text));
      result.push(text);
      if (result.length === 2) break;
    }
    return result;
  };
  const goal = (current.goal ?? "").trim() ? "" : line(reply.goal, MEMORY_TEXT);
  if (goal) known.add(key(goal));
  return { goal, decisions: pick(reply.decisions), questions: pick(reply.questions) };
}
function memoryBlock(memory) {
  const m = memory ?? {};
  const list = (value) => (Array.isArray(value) ? value : []).slice(0, 20).map((t) => line(t, 300)).filter(Boolean);
  const goal = line(m.goal, 300);
  const decisions = list(m.decisions);
  const questions = list(m.questions);
  return `Goal: ${goal || "none yet"}
Decisions: ${decisions.join("; ") || "none"}
Open questions: ${questions.join("; ") || "none"}`;
}
var QUIZ_LINK_RULE = ` Each idea has a "ref". Give every question "src": the ref of the one idea it is mostly about; leave "src" out when no single idea fits.`;
function treeRefs(node, into = /* @__PURE__ */ new Set()) {
  const item = node;
  if (typeof item?.ref === "string") into.add(item.ref);
  if (Array.isArray(item?.children)) for (const child of item.children) treeRefs(child, into);
  return into;
}
function cleanQuiz(raw, count, refs) {
  const list = raw?.questions;
  return (Array.isArray(list) ? list : []).flatMap((q) => {
    const options = Array.isArray(q?.options) ? q.options.filter((o) => typeof o === "string" && o.trim()).map((o) => clip(o.trim(), 160)) : [];
    const answer = Number(q?.answer);
    const question = typeof q?.question === "string" ? clip(q.question.trim(), 300) : "";
    if (!question || options.length < 2 || options.length > 5 || !Number.isInteger(answer) || answer < 0 || answer >= options.length) return [];
    const item = { question, options, answer, why: typeof q.why === "string" ? clip(q.why.trim(), 300) : "" };
    if (typeof q.src === "string" && refs.has(q.src)) item.src = q.src;
    return [item];
  }).slice(0, count);
}
export {
  MEMORY_TEXT,
  QUIZ_LINK_RULE,
  STEP_LIMIT,
  cleanMemory,
  cleanQuiz,
  cleanSteps,
  memoryBlock,
  treeRefs
};
