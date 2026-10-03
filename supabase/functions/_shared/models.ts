// The AI models Minor can use, what they cost, and what each plan may do with them.
//
// Chat: every model is open to every plan. Each request is charged its real API cost against the
// plan's monthly AI allowance (BUDGET_USD), so a frontier model simply uses the allowance faster.
// Maps: the strongest models are part of paid plans (MAP_TIERS).

export type Plan = "free" | "plus" | "pro";
export type Tier = "lite" | "standard" | "advanced" | "frontier";
export type Provider = "openai" | "anthropic";

export interface ModelInfo {
  id: string;
  provider: Provider;
  tier: Tier;
  input: number; // USD per million input tokens (list price)
  output: number; // USD per million output tokens
  tokenizer: number; // tokens per our 3-chars-per-token estimate (newer Claude models count ~30% more)
}

// List prices from openai.com and anthropic.com, October 2026.
export const CATALOG: ModelInfo[] = [
  { id: "gpt-6-luna", provider: "openai", tier: "lite", input: 0.1, output: 0.5, tokenizer: 1 },
  { id: "claude-haiku-4-5-20251001", provider: "anthropic", tier: "lite", input: 1, output: 5, tokenizer: 1 },
  { id: "gpt-6.1-sol", provider: "openai", tier: "standard", input: 2, output: 10, tokenizer: 1 },
  { id: "claude-sonnet-5-5", provider: "anthropic", tier: "standard", input: 2, output: 10, tokenizer: 1.3 },
  { id: "claude-opus-5-5", provider: "anthropic", tier: "advanced", input: 4, output: 20, tokenizer: 1.3 },
  { id: "gpt-6-astra", provider: "openai", tier: "frontier", input: 10, output: 50, tokenizer: 1 },
  { id: "claude-fable-5-1", provider: "anthropic", tier: "frontier", input: 10, output: 50, tokenizer: 1.3 },
];

const TIER_ORDER: Tier[] = ["lite", "standard", "advanced", "frontier"];

// Map quality each plan may choose. Free maps are built with a standard model.
export const MAP_TIERS: Record<Plan, Tier[]> = {
  free: ["standard"],
  plus: ["standard", "advanced"],
  pro: ["standard", "advanced", "frontier"],
};

// Monthly AI allowance in USD of API cost. It is the fair-use backstop behind the request counts
// in LIMITS: average use is a small part of it, and the heaviest use stays below what a
// subscription earns after Apple's commission and VAT.
export const BUDGET_USD: Record<Plan, number> = { free: 0.25, plus: 5, pro: 10 };

// Longest chat answer per plan (keeps one free message on a frontier model affordable).
export const CHAT_MAX_OUTPUT: Record<Plan, number> = { free: 1_500, plus: 4_096, pro: 8_192 };

export class ModelLockedError extends Error {}

export interface ResolvedModel {
  provider: Provider;
  model: string;
  tier: Tier;
  info: ModelInfo;
}

export function modelInfo(id: string): ModelInfo | null {
  return CATALOG.find((m) => m.id === id) ?? null;
}

// Picks a model of `tier`, preferring `provider` (then OpenAI) among providers with a key. When no
// configured provider has that exact tier, the nearest tier above it is used, then below.
export function modelForTier(
  tier: Tier,
  keys: { openai: boolean; anthropic: boolean },
  provider?: Provider,
  overrides: Partial<Record<string, string>> = {},
): ResolvedModel {
  const order: Provider[] = provider === "anthropic" ? ["anthropic", "openai"] : ["openai", "anthropic"];
  const start = TIER_ORDER.indexOf(tier);
  const tiers = [...TIER_ORDER.slice(start), ...TIER_ORDER.slice(0, start).reverse()];
  for (const t of tiers) {
    for (const p of order) {
      if (!keys[p]) continue;
      const info = CATALOG.find((m) => m.provider === p && m.tier === t);
      if (info) return { provider: p, tier: t, model: overrides[info.id] ?? info.id, info };
    }
  }
  throw new Error("no_provider");
}

// Chat: the requested model when it is known and its provider is configured, otherwise the cheapest
// model of the same provider family. Every plan may use every model.
export function resolveChatModel(
  requested: string | undefined,
  keys: { openai: boolean; anthropic: boolean },
  overrides: Partial<Record<string, string>> = {},
): ResolvedModel {
  const info = requested ? modelInfo(requested) : null;
  if (info && keys[info.provider]) {
    return { provider: info.provider, tier: info.tier, model: overrides[info.id] ?? info.id, info };
  }
  return modelForTier(info?.tier ?? "lite", keys, info?.provider, overrides);
}

// Maps: the requested model (or tier name) if the plan includes its tier. Lite models are not used
// for maps; a request for one gets the standard tier.
export function resolveMapModel(
  plan: Plan,
  requested: string | undefined,
  keys: { openai: boolean; anthropic: boolean },
  overrides: Partial<Record<string, string>> = {},
): ResolvedModel {
  const info = requested ? modelInfo(requested) : null;
  const named = (TIER_ORDER as string[]).includes(String(requested)) ? (requested as Tier) : null;
  let tier: Tier = info?.tier ?? named ?? "standard";
  if (tier === "lite") tier = "standard";
  if (!MAP_TIERS[plan].includes(tier)) throw new ModelLockedError(tier);
  if (info && info.tier === tier && keys[info.provider]) {
    return { provider: info.provider, tier, model: overrides[info.id] ?? info.id, info };
  }
  // Without a key for that exact tier, step down (never up past what the plan includes).
  const order: Provider[] = info?.provider === "anthropic" ? ["anthropic", "openai"] : ["openai", "anthropic"];
  const allowed = TIER_ORDER.slice(0, TIER_ORDER.indexOf(tier) + 1).reverse().filter((t) => t !== "lite");
  for (const t of allowed) {
    for (const p of order) {
      if (!keys[p]) continue;
      const found = CATALOG.find((m) => m.provider === p && m.tier === t);
      if (found) return { provider: p, tier: t, model: overrides[found.id] ?? found.id, info: found };
    }
  }
  throw new Error("no_provider");
}

// Cost of a call in millionths of a dollar (prices are USD per million tokens).
export function costMicros(info: ModelInfo, inputTokens: number, outputTokens: number): number {
  return Math.ceil(inputTokens * info.input + outputTokens * info.output);
}

// Worst-case cost before sending: ~3 characters per token (conservative for non-English text),
// ~1,600 tokens per photo, and the longest answer the model may write.
export function estimateMicros(info: ModelInfo, chars: number, images: number, maxOutput: number): number {
  const input = Math.ceil((chars / 3) * info.tokenizer) + images * 1_600;
  return costMicros(info, input, Math.ceil(maxOutput * info.tokenizer));
}

// Model tier for follow-up work on a map (expand, summarize, edit by command).
export const ACTION_TIER: Record<Plan, { light: Tier; edit: Tier }> = {
  free: { light: "lite", edit: "lite" },
  plus: { light: "standard", edit: "standard" },
  pro: { light: "standard", edit: "standard" },
};

// Source-size caps per plan, in characters (about 4 characters per token).
export const SOURCE_LIMITS: Record<Plan, number> = { free: 40_000, plus: 400_000, pro: 400_000 };

// Monthly request counts (on top of the AI allowance in BUDGET_USD).
export const LIMITS: Record<Plan, { maps: number; expands: number; chats: number; images: number }> = {
  free: { maps: 3, expands: 30, chats: 50, images: 3 },
  plus: { maps: 300, expands: 3_000, chats: 5_000, images: 60 },
  pro: { maps: 600, expands: 6_000, chats: 8_000, images: 150 },
};

// AI images (OpenAI). Prices per million tokens: text input, image input, image output.
export const IMAGE_MODEL = { id: "gpt-image-2", textInput: 5, imageInput: 8, output: 30 };
export type ImageQuality = "low" | "medium" | "high";

// Free images are low quality; Plus gets medium; PRO may ask for high.
export function imageQuality(plan: Plan, requested: unknown): ImageQuality {
  if (plan === "free") return "low";
  if (plan === "pro" && requested === "high") return "high";
  return "medium";
}

// Worst-case cost of one 1024×1024 image in micro-dollars (output tokens by quality, plus the prompt).
export function estimateImageMicros(quality: ImageQuality, promptChars: number): number {
  const output = quality === "low" ? 280 : quality === "medium" ? 2_000 : 7_800;
  return Math.ceil((promptChars / 3) * IMAGE_MODEL.textInput + output * IMAGE_MODEL.output);
}

export function imageCostMicros(usage: { input_tokens_details?: { text_tokens?: number; image_tokens?: number }; input_tokens?: number; output_tokens?: number }): number {
  const text = Number(usage.input_tokens_details?.text_tokens ?? usage.input_tokens ?? 0);
  const image = Number(usage.input_tokens_details?.image_tokens ?? 0);
  return Math.ceil(text * IMAGE_MODEL.textInput + image * IMAGE_MODEL.imageInput + Number(usage.output_tokens ?? 0) * IMAGE_MODEL.output);
}

// Link and video fetches per month. Counted separately and never refunded, so failing links can't
// turn the server into a free fetch proxy.
export const FETCH_LIMITS: Record<Plan, number> = { free: 20, plus: 1_000, pro: 2_000 };

// Hard caps on every field a client can send.
export const CAPS = {
  title: 200,
  pathItems: 12,
  existingItems: 50,
  childItems: 80,
  command: 1_000,
  editMapChars: 24_000,
  images: 4,
  imageChars: 1_600_000, // base64, about 1.2 MB of JPEG
  messages: 30,
  messageChars: { free: 8_000, plus: 40_000, pro: 60_000 } as Record<Plan, number>,
  chatChars: { free: 30_000, plus: 150_000, pro: 250_000 } as Record<Plan, number>,
};

export function clip(text: unknown, max: number): string {
  const s = String(text ?? "");
  return s.length > max ? s.slice(0, max - 1) + "…" : s;
}
