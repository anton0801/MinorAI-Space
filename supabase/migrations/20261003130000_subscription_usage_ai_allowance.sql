-- Paid allowances follow the subscription, not the account: moving one subscription between
-- (anonymous) accounts no longer starts a fresh month of maps, chats and AI spend.
create table public.subscription_usage (
  original_transaction_id text not null references public.subscriptions (original_transaction_id) on delete cascade,
  period text not null,
  maps integer not null default 0,
  expands integer not null default 0,
  chats integer not null default 0,
  spend_micros bigint not null default 0,
  primary key (original_transaction_id, period)
);
alter table public.subscription_usage enable row level security;
-- No policies: only edge functions (service role) read or write it.

create function public.consume_sub_quota(p_sub text, p_kind text, p_limit integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
  v_used integer;
begin
  insert into public.subscription_usage (original_transaction_id, period) values (p_sub, v_period)
    on conflict (original_transaction_id, period) do nothing;
  if p_kind = 'maps' then
    update public.subscription_usage set maps = maps + 1
      where original_transaction_id = p_sub and period = v_period and maps < p_limit
      returning maps into v_used;
  elsif p_kind = 'expands' then
    update public.subscription_usage set expands = expands + 1
      where original_transaction_id = p_sub and period = v_period and expands < p_limit
      returning expands into v_used;
  elsif p_kind = 'chats' then
    update public.subscription_usage set chats = chats + 1
      where original_transaction_id = p_sub and period = v_period and chats < p_limit
      returning chats into v_used;
  else
    raise exception 'unknown kind %', p_kind;
  end if;
  if v_used is null then
    return -1;
  end if;
  return p_limit - v_used;
end;
$$;

create function public.release_sub_quota(p_sub text, p_kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
begin
  if p_kind = 'maps' then
    update public.subscription_usage set maps = greatest(maps - 1, 0) where original_transaction_id = p_sub and period = v_period;
  elsif p_kind = 'expands' then
    update public.subscription_usage set expands = greatest(expands - 1, 0) where original_transaction_id = p_sub and period = v_period;
  elsif p_kind = 'chats' then
    update public.subscription_usage set chats = greatest(chats - 1, 0) where original_transaction_id = p_sub and period = v_period;
  end if;
end;
$$;

-- Monthly AI allowance in millionths of a dollar of API cost (each model is charged at its price).
alter table public.usage add column spend_micros bigint not null default 0;

-- Atomic allowance: a positive amount is reserved only if it fits under the limit (so parallel
-- requests can't all pass a stale check); zero or negative amounts (corrections, refunds) always apply.
-- Paid plans count against the subscription only, so a plan that lapses mid-month leaves the free
-- allowance untouched.
create function public.reserve_spend(p_user uuid, p_sub text, p_amount bigint, p_limit bigint)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
begin
  if p_sub is not null then
    insert into public.subscription_usage (original_transaction_id, period) values (p_sub, v_period)
      on conflict (original_transaction_id, period) do nothing;
    update public.subscription_usage set spend_micros = greatest(spend_micros + p_amount, 0)
      where original_transaction_id = p_sub and period = v_period
        and (p_amount <= 0 or spend_micros + p_amount <= p_limit);
    return found;
  end if;

  insert into public.usage (user_id, period) values (p_user, v_period)
    on conflict (user_id, period) do nothing;
  update public.usage set spend_micros = greatest(spend_micros + p_amount, 0)
    where user_id = p_user and period = v_period
      and (p_amount <= 0 or spend_micros + p_amount <= p_limit);
  return found;
end;
$$;

-- Link and video fetches are counted separately and never refunded, so failing fetches can't be
-- used as a free proxy.
alter table public.usage add column fetches integer not null default 0;

create function public.consume_fetch(p_user uuid, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
begin
  insert into public.usage (user_id, period) values (p_user, v_period)
    on conflict (user_id, period) do nothing;
  update public.usage set fetches = fetches + 1
    where user_id = p_user and period = v_period and fetches < p_limit;
  return found;
end;
$$;

-- Refunds: when the refund happened (so a later resubscription can lift it), and Apple's
-- notification time kept apart from the time of transactions the app presents.
alter table public.subscriptions add column revoked_at timestamptz;
alter table public.subscriptions add column last_notification_at timestamptz;

revoke execute on function public.consume_sub_quota(text, text, integer) from public, anon, authenticated;
revoke execute on function public.release_sub_quota(text, text) from public, anon, authenticated;
revoke execute on function public.reserve_spend(uuid, text, bigint, bigint) from public, anon, authenticated;
revoke execute on function public.consume_fetch(uuid, integer) from public, anon, authenticated;
grant execute on function public.consume_sub_quota(text, text, integer) to service_role;
grant execute on function public.release_sub_quota(text, text) to service_role;
grant execute on function public.reserve_spend(uuid, text, bigint, bigint) to service_role;
grant execute on function public.consume_fetch(uuid, integer) to service_role;
