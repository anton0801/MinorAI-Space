-- Invitations: everyone has a code; a friend who signs up with it gets free days of Plus, and so
-- does the person who invited them, once when the friend makes a first map and again when the
-- friend subscribes. Days of Plus run at once on the free plan, or wait (bonus_days) while a paid
-- plan is active and start when it ends.

alter table public.profiles
  add column bonus_until timestamptz,
  add column bonus_days integer not null default 0 check (bonus_days between 0 and 365);

create table public.referral_codes (
  user_id uuid primary key references auth.users (id) on delete cascade,
  code text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  created_at timestamptz not null default now()
);

-- One inviter per person, ever.
create table public.referrals (
  invitee uuid primary key references auth.users (id) on delete cascade,
  inviter uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  join_rewarded_at timestamptz,
  purchase_rewarded_at timestamptz,
  constraint referrals_not_self check (invitee <> inviter)
);
create index referrals_inviter on public.referrals (inviter, created_at);

-- Devices that already took an invitation (a hash of the device id; Apple's DeviceCheck is the
-- stronger guard, since it survives reinstalling the app).
create table public.referral_devices (
  device text primary key check (device ~ '^[0-9a-f]{64}$'),
  invitee uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.referral_codes enable row level security;
alter table public.referrals enable row level security;
alter table public.referral_devices enable row level security;
revoke all on public.referral_codes, public.referrals, public.referral_devices from public, anon, authenticated;

-- Days of Plus left to run (whole days, rounded up).
create function private.bonus_days_running(p_until timestamptz)
returns integer
language sql
stable
set search_path = ''
as $$
  select greatest(ceil(extract(epoch from (coalesce(p_until, now()) - now())) / 86400.0), 0)::integer;
$$;

create function private.has_paid_plan(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.subscriptions s
    where s.user_id = p_user and not s.revoked and s.expires_at > now()
  );
$$;

-- Adds days of Plus (at most 180 waiting and running together). Returns the days actually given.
create function public.grant_bonus_days(p_user uuid, p_days integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_add integer;
begin
  insert into public.profiles (id) values (p_user) on conflict (id) do nothing;
  select * into v_profile from public.profiles where id = p_user for update;
  v_add := least(greatest(p_days, 0), greatest(180 - private.bonus_days_running(v_profile.bonus_until) - v_profile.bonus_days, 0));
  if v_add = 0 then
    return 0;
  end if;
  if private.has_paid_plan(p_user) then
    update public.profiles set bonus_days = bonus_days + v_add, updated_at = now() where id = p_user;
  else
    update public.profiles
      set bonus_until = greatest(coalesce(bonus_until, now()), now()) + make_interval(days => bonus_days + v_add),
          bonus_days = 0,
          updated_at = now()
      where id = p_user;
  end if;
  return v_add;
end;
$$;

-- Starts waiting days once no paid plan is active. Returns when free Plus ends (null: none).
create function public.start_bonus(p_user uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_until timestamptz;
begin
  if not private.has_paid_plan(p_user) then
    update public.profiles
      set bonus_until = greatest(coalesce(bonus_until, now()), now()) + make_interval(days => bonus_days),
          bonus_days = 0,
          updated_at = now()
      where id = p_user and bonus_days > 0;
  end if;
  select bonus_until into v_until from public.profiles where id = p_user;
  return v_until;
end;
$$;

-- The app calls this for the signed-in person when it sees waiting days.
create function public.claim_bonus()
returns timestamptz
language sql
security definer
set search_path = ''
as $$
  select public.start_bonus(auth.uid());
$$;

-- A friend uses a code. Checked here, in one transaction: a real account at most 14 days old,
-- never invited before, a device that never took an invitation, not one's own code, and at most
-- 20 friends a month per code. The friend's 7 days start (or wait) at once.
create function public.redeem_referral(p_invitee uuid, p_code text, p_device text)
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
  if (select count(*) from public.referrals where inviter = v_inviter and created_at > now() - interval '30 days') >= 20 then
    raise exception 'invite_limit' using errcode = 'P0001';
  end if;
  if p_device is not null then
    insert into public.referral_devices (device, invitee) values (p_device, p_invitee) on conflict (device) do nothing;
    if not found then
      raise exception 'invite_device_used' using errcode = 'P0001';
    end if;
  end if;
  insert into public.referrals (invitee, inviter) values (p_invitee, v_inviter);
  v_days := public.grant_bonus_days(p_invitee, 7);
  return json_build_object('inviter', v_inviter, 'days', v_days);
end;
$$;

-- The friend made a first map: the inviter gets 7 days (at most 10 such rewards a month).
-- Returns the inviter, the days given and whether they wait for a paid plan to end, or null.
create function public.reward_referral_join(p_invitee uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inviter uuid;
  v_days integer := 0;
begin
  update public.referrals set join_rewarded_at = now()
    where invitee = p_invitee and join_rewarded_at is null
    returning inviter into v_inviter;
  if v_inviter is null then
    return null;
  end if;
  if (select count(*) from public.referrals where inviter = v_inviter and join_rewarded_at > now() - interval '30 days') <= 10 then
    v_days := public.grant_bonus_days(v_inviter, 7);
  end if;
  return json_build_object('inviter', v_inviter, 'days', v_days, 'waiting', private.has_paid_plan(v_inviter));
end;
$$;

-- The friend bought a subscription (App Store, not a test purchase): the inviter gets 30 days.
create function public.reward_referral_purchase(p_invitee uuid)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inviter uuid;
  v_days integer;
begin
  update public.referrals set purchase_rewarded_at = now()
    where invitee = p_invitee and purchase_rewarded_at is null
    returning inviter into v_inviter;
  if v_inviter is null then
    return null;
  end if;
  v_days := public.grant_bonus_days(v_inviter, 30);
  return json_build_object('inviter', v_inviter, 'days', v_days, 'waiting', private.has_paid_plan(v_inviter));
end;
$$;

-- Free Plus counts as Plus for shared maps too.
create or replace function public.active_plan(p_user uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case
      when p.plan <> 'free' and (p.plan_expires_at is null or p.plan_expires_at > now()) then p.plan
      when p.bonus_until > now() then 'plus'
      else 'free'
    end
    from public.profiles p where p.id = p_user
  ), 'free');
$$;

revoke execute on function private.bonus_days_running(timestamptz) from public, anon, authenticated;
revoke execute on function private.has_paid_plan(uuid) from public, anon, authenticated;
revoke execute on function public.grant_bonus_days(uuid, integer) from public, anon, authenticated;
revoke execute on function public.start_bonus(uuid) from public, anon, authenticated;
revoke execute on function public.redeem_referral(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.reward_referral_join(uuid) from public, anon, authenticated;
revoke execute on function public.reward_referral_purchase(uuid) from public, anon, authenticated;
revoke execute on function public.claim_bonus() from public, anon;
revoke execute on function public.active_plan(uuid) from public, anon, authenticated;
grant execute on function public.claim_bonus() to authenticated;
grant execute on function public.grant_bonus_days(uuid, integer) to service_role;
grant execute on function public.start_bonus(uuid) to service_role;
grant execute on function public.redeem_referral(uuid, text, text) to service_role;
grant execute on function public.reward_referral_join(uuid) to service_role;
grant execute on function public.reward_referral_purchase(uuid) to service_role;
