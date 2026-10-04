// Invitation rewards that follow what an invited friend does (see migration "referrals").
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { sendPush } from "./push.ts";
import { PUSH } from "./pushText.ts";

// Days of Minor Plus: for the friend who joins with a code, and for the person who invited them
// when the friend makes a first map. When the friend subscribes, the inviter gets a discount on
// any subscription (a one-time App Store offer code). At most INVITE_LIMIT friends per code.
export const INVITE_DAYS = { friend: 3, join: 3 };
export const INVITE_LIMIT = 3;
export const DISCOUNT_PERCENT = 30;

// Subscriptions a discount can be for (the legacy half-year plan is no longer sold).
export const DISCOUNT_PRODUCTS = [
  "com.minorailifegroup.MinorAI.plusMonthlyPlan",
  "com.minorailifegroup.MinorAI.plusYearlyPlan",
  "com.minorailifegroup.MinorAI.proMonthlyPlan",
  "com.minorailifegroup.MinorAI.proYearlyPlan",
];

// Opens the App Store's redemption screen with the code filled in.
export function redeemURL(code: string): string {
  return `https://apps.apple.com/redeem?ctx=offercodes&id=6737686540&code=${encodeURIComponent(code)}`;
}

// Codes: 8 characters without look-alikes (no 0/O, 1/I).
export const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export function newCode(random: (n: number) => Uint8Array = (n) => crypto.getRandomValues(new Uint8Array(n))): string {
  return Array.from(random(8), (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join("");
}

export function cleanCode(raw: unknown): string | null {
  const code = String(raw ?? "").toUpperCase().replace(/[\s-]/g, "");
  return /^[A-HJ-NP-Z2-9]{8}$/.test(code) ? code : null;
}

interface Reward {
  inviter: string;
  days: number;
  waiting?: boolean;
  discount?: boolean;
}

// The friend made a first map. Cheap when there is nothing to reward (one indexed update).
export async function rewardJoin(supabase: SupabaseClient, userId: string): Promise<void> {
  const { data, error } = await supabase.rpc("reward_referral_join", { p_invitee: userId });
  const reward = data as Reward | null;
  if (error || !reward?.inviter || !reward.days) return;
  await sendPush(supabase, [reward.inviter], "account", {
    text: PUSH.friendJoined(reward.days, reward.waiting === true),
    route: "minorai://invite",
    thread: "invite",
  });
}

// A paid period in the App Store: not a test purchase and not a free trial (a trial that turns
// into a paid subscription counts when it renews).
export function isPaidTransaction(transaction: Record<string, unknown>): boolean {
  if (String(transaction.environment ?? "Production") !== "Production") return false;
  if (transaction.offerDiscountType === "FREE_TRIAL") return false;
  if (transaction.price !== undefined && Number(transaction.price) === 0) return false;
  return true;
}

// The friend paid for a subscription: whoever invited them gets a discount to claim (once).
export async function rewardPurchase(supabase: SupabaseClient, userId: string | null, transaction: Record<string, unknown>): Promise<void> {
  if (!userId || !isPaidTransaction(transaction)) return;
  const { data, error } = await supabase.rpc("reward_referral_purchase", { p_invitee: userId });
  const reward = data as Reward | null;
  if (error || !reward?.inviter) return;
  await sendPush(supabase, [reward.inviter], "account", {
    text: PUSH.friendSubscribed(DISCOUNT_PERCENT),
    route: "minorai://invite",
    thread: "invite",
  });
}
