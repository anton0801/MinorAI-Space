// The plan a user has right now: from their active App Store subscriptions, or free days of Plus
// from invitations.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { BONUS_BUDGET_USD, BUDGET_USD, type Plan } from "./models.ts";

export interface ActivePlan {
  plan: Plan;
  // originalTransactionId of the subscription that grants the plan. Paid allowances are counted
  // against it, so moving a subscription between accounts doesn't reset them.
  subscription: string | null;
  // Bought in the App Store sandbox (TestFlight, App Review): real allowances aren't given for it.
  sandbox: boolean;
  // Free Plus from invitations runs until then (no subscription; counted on the account).
  bonusUntil?: string | null;
}

export async function currentSubscription(supabase: SupabaseClient, userId: string): Promise<ActivePlan> {
  const { data } = await supabase
    .from("subscriptions")
    .select("original_transaction_id, plan, expires_at, environment")
    .eq("user_id", userId)
    .eq("revoked", false)
    .gt("expires_at", new Date().toISOString());
  const rows = (data ?? []) as { original_transaction_id: string; plan: string; expires_at: string; environment: string }[];
  const best = rows.find((row) => row.plan === "pro") ?? rows.find((row) => row.plan === "plus");
  if (best) return { plan: best.plan as Plan, subscription: best.original_transaction_id, sandbox: best.environment !== "Production" };

  // Days of Plus that waited for a paid plan to end start now.
  const { data: profile } = await supabase.from("profiles").select("bonus_until, bonus_days").eq("id", userId).maybeSingle();
  let until = (profile?.bonus_until as string | null | undefined) ?? null;
  if (Number(profile?.bonus_days ?? 0) > 0) {
    const { data: started } = await supabase.rpc("start_bonus", { p_user: userId });
    if (typeof started === "string") until = started;
  }
  if (until && Date.parse(until) > Date.now()) return { plan: "plus", subscription: null, sandbox: false, bonusUntil: until };
  return { plan: "free", subscription: null, sandbox: false };
}

export async function currentPlan(supabase: SupabaseClient, userId: string): Promise<Plan> {
  return (await currentSubscription(supabase, userId)).plan;
}

// This month's AI allowance in millionths of a dollar. Test purchases (TestFlight, App Review)
// unlock the plan's features with at most $5 of AI, enough for a reviewer to try everything;
// free Plus from invitations gets a smaller allowance than a paid one.
export function budgetMicros(active: ActivePlan): number {
  let usd = BUDGET_USD[active.plan];
  if (active.sandbox) usd = Math.min(usd, 5);
  if (active.bonusUntil) usd = Math.min(usd, BONUS_BUDGET_USD);
  return Math.round(usd * 1_000_000);
}
