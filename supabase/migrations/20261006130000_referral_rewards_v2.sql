-- Invitations, second version: 3 days of Plus for the friend and 3 for the person who invited
-- them (when the friend makes a first map), a 30% discount on any subscription for the inviter
-- when the friend subscribes, and at most 3 friends per code.
--
-- The discount is an App Store offer code: one-time codes are made in App Store Connect for each
-- subscription and loaded here with import_offer_codes; each code goes to one inviter, who picks
-- the subscription it is for.

alter table public.referrals
  add column discount_code text,
  add column discount_product text,
  add column discount_claimed_at timestamptz;

create table public.offer_codes (
  code text primary key check (code ~ '^[A-Z0-9]{4,64}$'),
  product text not null check (product in (
    'com.minorailifegroup.MinorAI.plusMonthlyPlan',
    'com.minorailifegroup.MinorAI.plusYearlyPlan',
    'com.minorailifegroup.MinorAI.proMonthlyPlan',
    'com.minorailifegroup.MinorAI.proYearlyPlan'
  )),
  assigned_to uuid references auth.users (id) on delete set null,
  assigned_at timestamptz,
  created_at timestamptz not null default now()
);
create index offer_codes_free on public.offer_codes (product) where assigned_at is null;

alter table public.offer_codes enable row level security;
revoke all on public.offer_codes from public, anon, authenticated;

-- A friend uses a code: as before, but 3 days of Plus and at most 3 friends per code, ever.
create or replace function public.redeem_referral(p_invitee uuid, p_code text, p_device text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inviter uuid;
  v_user auth.users;
  v_days integer;
begin
  select user_id into v_inviter from public.referral_codes where code = upper(trim(p_code));
  if v_inviter is null then
    raise exception 'invite_not_found' using errcode = 'P0001';
  end if;
  if v_inviter = p_invitee then
    raise exception 'invite_own_code' using errcode = 'P0001';
  end if;
  select * into v_user from auth.users where id = p_invitee;
  if v_user.id is null or coalesce(v_user.is_anonymous, false) then
    raise exception 'sign_in_required' using errcode = 'P0001';
  end if;
  if v_user.created_at < now() - interval '14 days' then
    raise exception 'invite_too_late' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.referrals where invitee = p_invitee) then
    raise exception 'invite_used' using errcode = 'P0001';
  end if;
  -- Serializes redemptions of one code, so parallel requests can't pass the limit together.
  perform 1 from public.referral_codes where user_id = v_inviter for update;
  if (select count(*) from public.referrals where inviter = v_inviter) >= 3 then
    raise exception 'invite_limit' using errcode = 'P0001';
  end if;
  if p_device is not null then
    insert into public.referral_devices (device, invitee) values (p_device, p_invitee) on conflict (device) do nothing;
    if not found then
      raise exception 'invite_device_used' using errcode = 'P0001';
    end if;
  end if;
  insert into public.referrals (invitee, inviter) values (p_invitee, v_inviter);
  v_days := public.grant_bonus_days(p_invitee, 3);
  return json_build_object('inviter', v_inviter, 'days', v_days);
end;
$$;

-- The friend made a first map: the inviter gets 3 days.
create or replace function public.reward_referral_join(p_invitee uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inviter uuid;
  v_days integer;
begin
  update public.referrals set join_rewarded_at = now()
    where invitee = p_invitee and join_rewarded_at is null
    returning inviter into v_inviter;
  if v_inviter is null then
    return null;
  end if;
  v_days := public.grant_bonus_days(v_inviter, 3);
  return json_build_object('inviter', v_inviter, 'days', v_days, 'waiting', private.has_paid_plan(v_inviter));
end;
$$;

-- The friend paid for a subscription: the inviter gets a discount to claim (no days any more).
create or replace function public.reward_referral_purchase(p_invitee uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inviter uuid;
begin
  update public.referrals set purchase_rewarded_at = now()
    where invitee = p_invitee and purchase_rewarded_at is null
    returning inviter into v_inviter;
  if v_inviter is null then
    return null;
  end if;
  return json_build_object('inviter', v_inviter, 'days', 0, 'discount', true);
end;
$$;

-- The inviter picks the subscription for an earned discount and gets a one-time offer code for it.
create function public.claim_referral_discount(p_inviter uuid, p_product text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invitee uuid;
  v_code text;
begin
  select invitee into v_invitee from public.referrals
    where inviter = p_inviter and purchase_rewarded_at is not null and discount_code is null
    order by purchase_rewarded_at
    limit 1
    for update;
  if v_invitee is null then
    raise exception 'no_discount' using errcode = 'P0001';
  end if;
  select code into v_code from public.offer_codes
    where product = p_product and assigned_at is null
    limit 1
    for update skip locked;
  if v_code is null then
    raise exception 'no_codes' using errcode = 'P0001';
  end if;
  update public.offer_codes set assigned_to = p_inviter, assigned_at = now() where code = v_code;
  update public.referrals
    set discount_code = v_code, discount_product = p_product, discount_claimed_at = now()
    where invitee = v_invitee;
  return v_code;
end;
$$;

-- Loads one-time offer codes for a subscription from the file App Store Connect gives (any
-- separators; a header line is skipped). Run in the SQL editor:
--   select public.import_offer_codes('com.minorailifegroup.MinorAI.plusMonthlyPlan', $codes$ …paste… $codes$);
-- Returns how many new codes were added.
create function public.import_offer_codes(p_product text, p_codes text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into public.offer_codes (code, product)
    select distinct upper(trim(c)), p_product
    from regexp_split_to_table(coalesce(p_codes, ''), '[\s,;"]+') as c
    where upper(trim(c)) ~ '^[A-Z0-9]{4,64}$'
      and upper(trim(c)) not in ('CODE', 'CODES', 'OFFER', 'ONE', 'TIME', 'USE', 'EXPIRATION', 'DATE')
    on conflict (code) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.claim_referral_discount(uuid, text) from public, anon, authenticated;
revoke execute on function public.import_offer_codes(text, text) from public, anon, authenticated, service_role;
grant execute on function public.claim_referral_discount(uuid, text) to service_role;
