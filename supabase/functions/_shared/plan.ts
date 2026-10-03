// The plan a user has right now, from their active App Store subscriptions.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { Plan } from "./models.ts";

export interface ActivePlan {
  plan: Plan;
  // originalTransactionId of the subscription that grants the plan. Paid allowances are counted
  // against it, so moving a subscription between accounts doesn't reset them.
  subscription: string | null;
}

export async function currentSubscription(supabase: SupabaseClient, userId: string): Promise<ActivePlan> {
  const { data } = await supabase
    .from("subscriptions")
    .select("original_transaction_id, plan, expires_at")
    .eq("user_id", userId)
    .eq("revoked", false)
    .gt("expires_at", new Date().toISOString());
  const rows = (data ?? []) as { original_transaction_id: string; plan: string; expires_at: string }[];
  const best = rows.find((row) => row.plan === "pro") ?? rows.find((row) => row.plan === "plus");
  return best ? { plan: best.plan as Plan, subscription: best.original_transaction_id } : { plan: "free", subscription: null };
}

export async function currentPlan(supabase: SupabaseClient, userId: string): Promise<Plan> {
  return (await currentSubscription(supabase, userId)).plan;
}
