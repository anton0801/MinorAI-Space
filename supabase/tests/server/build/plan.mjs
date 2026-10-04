// ../../functions/_shared/models.ts
var BUDGET_USD = { free: 0.25, plus: 5, pro: 10 };
var BONUS_BUDGET_USD = 2;

// ../../functions/_shared/plan.ts
async function currentSubscription(supabase, userId) {
  const { data } = await supabase.from("subscriptions").select("original_transaction_id, plan, expires_at, environment").eq("user_id", userId).eq("revoked", false).gt("expires_at", (/* @__PURE__ */ new Date()).toISOString());
  const rows = data ?? [];
  const best = rows.find((row) => row.plan === "pro") ?? rows.find((row) => row.plan === "plus");
  if (best) return { plan: best.plan, subscription: best.original_transaction_id, sandbox: best.environment !== "Production" };
  const { data: profile } = await supabase.from("profiles").select("bonus_until, bonus_days").eq("id", userId).maybeSingle();
  let until = profile?.bonus_until ?? null;
  if (Number(profile?.bonus_days ?? 0) > 0) {
    const { data: started } = await supabase.rpc("start_bonus", { p_user: userId });
    if (typeof started === "string") until = started;
  }
  if (until && Date.parse(until) > Date.now()) return { plan: "plus", subscription: null, sandbox: false, bonusUntil: until };
  return { plan: "free", subscription: null, sandbox: false };
}
async function currentPlan(supabase, userId) {
  return (await currentSubscription(supabase, userId)).plan;
}
function budgetMicros(active) {
  let usd = BUDGET_USD[active.plan];
  if (active.sandbox) usd = Math.min(usd, 5);
  if (active.bonusUntil) usd = Math.min(usd, BONUS_BUDGET_USD);
  return Math.round(usd * 1e6);
}
export {
  budgetMicros,
  currentPlan,
  currentSubscription
};
