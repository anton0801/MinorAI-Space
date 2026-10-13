// Continuing work on a project (a map): next steps for an idea, and suggestions for the project's
// summary (goal, decisions, open questions). The AI's replies are checked here: lengths, counts,
// nothing the user already has, and no empty or duplicate lines.

import { clip } from "./models.ts";

export const STEP_LIMIT = 3;
export const MEMORY_TEXT = 120;

export interface Step {
  title: string;
  detail: string;
}

export interface MemorySuggestions {
  goal: string;
  decisions: string[];
  questions: string[];
}

function key(text: string): string {
  return text.toLowerCase().replace(/[\s.!?…,;:"'«»“”()-]+/g, " ").trim();
}

function line(raw: unknown, max: number): string {
  return clip(String(raw ?? "").replace(/\s+/g, " ").trim(), max).replace(/^[-•*\d.)\s]+/, "").trim();
}

// At most three steps, each a short action, none repeating what the idea already has.
export function cleanSteps(raw: unknown, existing: string[]): Step[] {
  const list = Array.isArray((raw as { steps?: unknown })?.steps) ? (raw as { steps: unknown[] }).steps : [];
  const seen = new Set(existing.map(key));
  const steps: Step[] = [];
  for (const item of list) {
    const title = line((item as Step)?.title, 80);
    if (!title || seen.has(key(title))) continue;
    seen.add(key(title));
    steps.push({ title, detail: line((item as Step)?.detail, 100) });
    if (steps.length === STEP_LIMIT) break;
  }
  return steps;
}

// Up to two decisions and two questions, and a goal only when the user has none.
export function cleanMemory(raw: unknown, current: { goal?: string; decisions?: string[]; questions?: string[] }): MemorySuggestions {
  const reply = (raw ?? {}) as Record<string, unknown>;
  const known = new Set([...(current.decisions ?? []), ...(current.questions ?? []), current.goal ?? ""].map(key).filter(Boolean));
  const pick = (value: unknown) => {
    const result: string[] = [];
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

// The user's summary as the AI sees it.
export function memoryBlock(memory: unknown): string {
  const m = (memory ?? {}) as Record<string, unknown>;
  const list = (value: unknown) => (Array.isArray(value) ? value : []).slice(0, 20).map((t) => line(t, 300)).filter(Boolean);
  const goal = line(m.goal, 300);
  const decisions = list(m.decisions);
  const questions = list(m.questions);
  return `Goal: ${goal || "none yet"}\nDecisions: ${decisions.join("; ") || "none"}\nOpen questions: ${questions.join("; ") || "none"}`;
}

// Study → Quiz. When the map's ideas carry refs ("n7"), each question may name the idea it is about;
// a ref the map doesn't have is dropped, so the app never links a made-up idea.
export const QUIZ_LINK_RULE =
  ` Each idea has a "ref". Give every question "src": the ref of the one idea it is mostly about; leave "src" out when no single idea fits.`;

export interface QuizQuestion {
  question: string;
  options: string[];
  answer: number;
  why: string;
  src?: string;
}

// Refs of every idea in a tree ({ ref?, children? }).
export function treeRefs(node: unknown, into = new Set<string>()): Set<string> {
  const item = node as { ref?: unknown; children?: unknown };
  if (typeof item?.ref === "string") into.add(item.ref);
  if (Array.isArray(item?.children)) for (const child of item.children) treeRefs(child, into);
  return into;
}

export function cleanQuiz(raw: unknown, count: number, refs: Set<string>): QuizQuestion[] {
  const list = (raw as { questions?: unknown })?.questions;
  return (Array.isArray(list) ? list : []).flatMap((q: any) => {
    const options = Array.isArray(q?.options) ? q.options.filter((o: unknown) => typeof o === "string" && o.trim()).map((o: string) => clip(o.trim(), 160)) : [];
    const answer = Number(q?.answer);
    const question = typeof q?.question === "string" ? clip(q.question.trim(), 300) : "";
    if (!question || options.length < 2 || options.length > 5 || !Number.isInteger(answer) || answer < 0 || answer >= options.length) return [];
    const item: QuizQuestion = { question, options, answer, why: typeof q.why === "string" ? clip(q.why.trim(), 300) : "" };
    if (typeof q.src === "string" && refs.has(q.src)) item.src = q.src;
    return [item];
  }).slice(0, count);
}
