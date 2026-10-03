// Bookkeeping for App Store subscriptions, keyed by originalTransactionId.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

export const BUNDLE_ID = "com.minorailifegroup.MinorAI";

// App Store Connect product IDs. The half-year Plus plan is no longer sold but still honored.
export const PLANS: Record<string, "plus" | "pro"> = {
  "com.minorailifegroup.MinorAI.plusMonthlyPlan": "plus",
  "com.minorailifegroup.MinorAI.plusHalfYearPlan": "plus",
  "com.minorailifegroup.MinorAI.plusYearlyPlan": "plus",
  "com.minorailifegroup.MinorAI.proMonthlyPlan": "pro",
  "com.minorailifegroup.MinorAI.proYearlyPlan": "pro",
};

export interface SubscriptionRow {
  original_transaction_id: string;
  user_id: string | null;
  product_id: string;
  plan: "plus" | "pro";
  expires_at: string | null;
  environment: string;
  revoked: boolean;
  last_signed_at: string;
  revoked_at?: string | null;
  last_notification_at?: string | null;
}

export async function findSubscription(supabase: SupabaseClient, originalTransactionId: string): Promise<SubscriptionRow | null> {
  const { data } = await supabase
    .from("subscriptions")
    .select("*")
    .eq("original_transaction_id", originalTransactionId)
    .maybeSingle();
  return (data as SubscriptionRow | null) ?? null;
}

// Throws the database error (with its Postgres `code`) when the row can't be written.
export async function saveSubscription(supabase: SupabaseClient, row: SubscriptionRow) {
  const { error } = await supabase
    .from("subscriptions")
    .upsert({ ...row, updated_at: new Date().toISOString() }, { onConflict: "original_transaction_id" });
  if (error) throw error;
}

export async function recomputePlan(supabase: SupabaseClient, userId: string | null): Promise<string> {
  if (!userId) return "free";
  const { data, error } = await supabase.rpc("recompute_plan", { p_user: userId });
  if (error) throw error;
  return String(data ?? "free");
}

export function isUUID(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

export function later(a: string | null, b: string | null): string | null {
  if (!a) return b;
  if (!b) return a;
  return time(a) > time(b) ? a : b;
}

// Milliseconds of an ISO date. Postgres and JavaScript write the same instant differently
// ("…24.12+00:00" vs "…24.120Z"), so dates are never compared as strings.
export function time(iso: string | null | undefined): number {
  const value = iso ? Date.parse(iso) : NaN;
  return Number.isFinite(value) ? value : 0;
}
