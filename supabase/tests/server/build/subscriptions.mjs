// ../../functions/_shared/subscriptions.ts
var BUNDLE_ID = "com.minorailifegroup.MinorAI";
var PLANS = {
  "com.minorailifegroup.MinorAI.plusMonthlyPlan": "plus",
  "com.minorailifegroup.MinorAI.plusHalfYearPlan": "plus",
  "com.minorailifegroup.MinorAI.plusYearlyPlan": "plus",
  "com.minorailifegroup.MinorAI.proMonthlyPlan": "pro",
  "com.minorailifegroup.MinorAI.proYearlyPlan": "pro"
};
async function findSubscription(supabase, originalTransactionId) {
  const { data } = await supabase.from("subscriptions").select("*").eq("original_transaction_id", originalTransactionId).maybeSingle();
  return data ?? null;
}
async function saveSubscription(supabase, row) {
  const { error } = await supabase.from("subscriptions").upsert({ ...row, updated_at: (/* @__PURE__ */ new Date()).toISOString() }, { onConflict: "original_transaction_id" });
  if (error) throw error;
}
async function recomputePlan(supabase, userId) {
  if (!userId) return "free";
  const { data, error } = await supabase.rpc("recompute_plan", { p_user: userId });
  if (error) throw error;
  return String(data ?? "free");
}
function isUUID(value) {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}
function later(a, b) {
  if (!a) return b;
  if (!b) return a;
  return time(a) > time(b) ? a : b;
}
function time(iso) {
  const value = iso ? Date.parse(iso) : NaN;
  return Number.isFinite(value) ? value : 0;
}
export {
  BUNDLE_ID,
  PLANS,
  findSubscription,
  isUUID,
  later,
  recomputePlan,
  saveSubscription,
  time
};
