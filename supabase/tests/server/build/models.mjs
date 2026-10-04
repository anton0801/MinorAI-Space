// ../../functions/_shared/models.ts
var CATALOG = [
  { id: "gpt-6-luna", provider: "openai", tier: "lite", input: 0.1, output: 0.5, tokenizer: 1 },
  { id: "claude-haiku-4-5-20251001", provider: "anthropic", tier: "lite", input: 1, output: 5, tokenizer: 1 },
  { id: "gpt-6.1-sol", provider: "openai", tier: "standard", input: 2, output: 10, tokenizer: 1 },
  { id: "claude-sonnet-5-5", provider: "anthropic", tier: "standard", input: 2, output: 10, tokenizer: 1.3 },
  { id: "claude-opus-5-5", provider: "anthropic", tier: "advanced", input: 4, output: 20, tokenizer: 1.3 },
  { id: "gpt-6-astra", provider: "openai", tier: "frontier", input: 10, output: 50, tokenizer: 1 },
  { id: "claude-fable-5-1", provider: "anthropic", tier: "frontier", input: 10, output: 50, tokenizer: 1.3 }
];
var TIER_ORDER = ["lite", "standard", "advanced", "frontier"];
var MAP_TIERS = {
  free: ["standard"],
  plus: ["standard", "advanced"],
  pro: ["standard", "advanced", "frontier"]
};
var BUDGET_USD = { free: 0.25, plus: 5, pro: 10 };
var BONUS_BUDGET_USD = 2;
function areaOf(action) {
  if (["map", "template", "expand", "edit", "summarize", "quiz"].includes(action)) return "maps";
  if (["deck", "slide", "deckEdit", "deckStyle", "slideElements"].includes(action)) return "decks";
  if (action === "chat") return "chat";
  if (action === "image") return "images";
  return null;
}
var CHAT_MAX_OUTPUT = { free: 1500, plus: 4096, pro: 8192 };
var ModelLockedError = class extends Error {
};
function modelInfo(id) {
  return CATALOG.find((m) => m.id === id) ?? null;
}
function modelForTier(tier, keys, provider, overrides = {}) {
  const order = provider === "anthropic" ? ["anthropic", "openai"] : ["openai", "anthropic"];
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
function resolveChatModel(requested, keys, overrides = {}) {
  const info = requested ? modelInfo(requested) : null;
  if (info && keys[info.provider]) {
    return { provider: info.provider, tier: info.tier, model: overrides[info.id] ?? info.id, info };
  }
  return modelForTier(info?.tier ?? "lite", keys, info?.provider, overrides);
}
function resolveMapModel(plan, requested, keys, overrides = {}) {
  const info = requested ? modelInfo(requested) : null;
  const named = TIER_ORDER.includes(String(requested)) ? requested : null;
  let tier = info?.tier ?? named ?? "standard";
  if (tier === "lite") tier = "standard";
  if (!MAP_TIERS[plan].includes(tier)) throw new ModelLockedError(tier);
  if (info && info.tier === tier && keys[info.provider]) {
    return { provider: info.provider, tier, model: overrides[info.id] ?? info.id, info };
  }
  const order = info?.provider === "anthropic" ? ["anthropic", "openai"] : ["openai", "anthropic"];
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
function costMicros(info, inputTokens, outputTokens) {
  return Math.ceil(inputTokens * info.input + outputTokens * info.output);
}
function textUnits(text) {
  let units = 0;
  for (let i = 0; i < text.length; i++) units += text.charCodeAt(i) < 128 ? 1 : 3;
  return units;
}
function estimateMicros(info, chars, images, maxOutput) {
  const input = Math.ceil(chars / 3 * info.tokenizer) + images * 1600;
  return costMicros(info, input, Math.ceil(maxOutput * info.tokenizer));
}
var ACTION_TIER = {
  free: { light: "lite", edit: "lite" },
  plus: { light: "standard", edit: "standard" },
  pro: { light: "standard", edit: "standard" }
};
var SOURCE_LIMITS = { free: 4e4, plus: 4e5, pro: 4e5 };
var LIMITS = {
  free: { maps: 3, expands: 30, chats: 50, images: 3, decks: 1 },
  plus: { maps: 300, expands: 3e3, chats: 5e3, images: 60, decks: 20 },
  pro: { maps: 600, expands: 6e3, chats: 8e3, images: 150, decks: 60 }
};
var DECK_SLIDES = {
  free: { max: 8, default: 7 },
  plus: { max: 20, default: 10 },
  pro: { max: 30, default: 12 }
};
var IMAGE_MODEL = { id: "gpt-image-2", textInput: 5, imageInput: 8, output: 30 };
function imageQuality(plan, requested) {
  if (plan === "free") return "low";
  if (plan === "pro" && requested === "high") return "high";
  return "medium";
}
function estimateImageMicros(quality, promptChars) {
  const output = quality === "low" ? 280 : quality === "medium" ? 2e3 : 7800;
  return Math.ceil(promptChars / 3 * IMAGE_MODEL.textInput + output * IMAGE_MODEL.output);
}
function imageCostMicros(usage) {
  const text = Number(usage.input_tokens_details?.text_tokens ?? usage.input_tokens ?? 0);
  const image = Number(usage.input_tokens_details?.image_tokens ?? 0);
  return Math.ceil(text * IMAGE_MODEL.textInput + image * IMAGE_MODEL.imageInput + Number(usage.output_tokens ?? 0) * IMAGE_MODEL.output);
}
var FETCH_LIMITS = { free: 20, plus: 1e3, pro: 2e3 };
var CAPS = {
  title: 200,
  pathItems: 12,
  existingItems: 50,
  childItems: 80,
  command: 1e3,
  editMapChars: 24e3,
  images: 4,
  imageChars: 16e5,
  // base64, about 1.2 MB of JPEG
  messages: 30,
  messageChars: { free: 8e3, plus: 4e4, pro: 6e4 },
  chatChars: { free: 3e4, plus: 15e4, pro: 25e4 }
};
function clip(text, max) {
  const s = String(text ?? "");
  if (s.length <= max) return s;
  let cut = max - 1;
  const last = s.charCodeAt(cut - 1);
  if (last >= 55296 && last <= 56319) cut -= 1;
  return s.slice(0, cut) + "\u2026";
}
export {
  ACTION_TIER,
  BONUS_BUDGET_USD,
  BUDGET_USD,
  CAPS,
  CATALOG,
  CHAT_MAX_OUTPUT,
  DECK_SLIDES,
  FETCH_LIMITS,
  IMAGE_MODEL,
  LIMITS,
  MAP_TIERS,
  ModelLockedError,
  SOURCE_LIMITS,
  areaOf,
  clip,
  costMicros,
  estimateImageMicros,
  estimateMicros,
  imageCostMicros,
  imageQuality,
  modelForTier,
  modelInfo,
  resolveChatModel,
  resolveMapModel,
  textUnits
};
