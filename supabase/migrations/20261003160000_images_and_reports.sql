-- AI images get their own monthly count, next to maps, expands and chats; and people can report
-- AI output they find offensive (App Store Review 1.2 for generated content).

alter table public.usage add column images integer not null default 0;
alter table public.device_usage add column images integer not null default 0;
alter table public.subscription_usage add column images integer not null default 0;

-- The quota functions now take any counter from a fixed list (a whitelisted column name is
-- formatted into the statement, so no caller text ever becomes SQL).
create or replace function public.consume_quota(p_user uuid, p_kind text, p_limit integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
  v_used integer;
begin
  if p_kind not in ('maps', 'expands', 'chats', 'images') then
    raise exception 'unknown quota kind %', p_kind;
  end if;
  insert into public.usage (user_id, period) values (p_user, v_period)
    on conflict (user_id, period) do nothing;
  execute format(
    'update public.usage set %1$I = %1$I + 1 where user_id = $1 and period = $2 and %1$I < $3 returning %1$I', p_kind
  ) into v_used using p_user, v_period, p_limit;
  if v_used is null then
    return -1;
  end if;
  return p_limit - v_used;
end;
$$;

create or replace function public.release_quota(p_user uuid, p_kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
begin
  if p_kind not in ('maps', 'expands', 'chats', 'images') then
    return;
  end if;
  execute format(
    'update public.usage set %1$I = greatest(%1$I - 1, 0) where user_id = $1 and period = $2', p_kind
  ) using p_user, v_period;
end;
$$;

create or replace function public.consume_device_quota(p_device text, p_kind text, p_limit integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
  v_used integer;
begin
  if p_kind not in ('maps', 'expands', 'chats', 'images') then
    raise exception 'unknown quota kind %', p_kind;
  end if;
  insert into public.device_usage (device_id, period) values (p_device, v_period)
    on conflict (device_id, period) do nothing;
  execute format(
    'update public.device_usage set %1$I = %1$I + 1 where device_id = $1 and period = $2 and %1$I < $3 returning %1$I', p_kind
  ) into v_used using p_device, v_period, p_limit;
  if v_used is null then
    return -1;
  end if;
  return p_limit - v_used;
end;
$$;

create or replace function public.release_device_quota(p_device text, p_kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
begin
  if p_kind not in ('maps', 'expands', 'chats', 'images') then
    return;
  end if;
  execute format(
    'update public.device_usage set %1$I = greatest(%1$I - 1, 0) where device_id = $1 and period = $2', p_kind
  ) using p_device, v_period;
end;
$$;

create or replace function public.consume_sub_quota(p_sub text, p_kind text, p_limit integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
  v_used integer;
begin
  if p_kind not in ('maps', 'expands', 'chats', 'images') then
    raise exception 'unknown quota kind %', p_kind;
  end if;
  insert into public.subscription_usage (original_transaction_id, period) values (p_sub, v_period)
    on conflict (original_transaction_id, period) do nothing;
  execute format(
    'update public.subscription_usage set %1$I = %1$I + 1 where original_transaction_id = $1 and period = $2 and %1$I < $3 returning %1$I', p_kind
  ) into v_used using p_sub, v_period, p_limit;
  if v_used is null then
    return -1;
  end if;
  return p_limit - v_used;
end;
$$;

create or replace function public.release_sub_quota(p_sub text, p_kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
begin
  if p_kind not in ('maps', 'expands', 'chats', 'images') then
    return;
  end if;
  execute format(
    'update public.subscription_usage set %1$I = greatest(%1$I - 1, 0) where original_transaction_id = $1 and period = $2', p_kind
  ) using p_sub, v_period;
end;
$$;

-- Reports of AI output (images or answers) people found offensive or wrong.
create table public.reports (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users (id) on delete set null,
  kind text not null check (kind in ('image', 'answer', 'map')),
  content text not null,
  reason text,
  created_at timestamptz not null default now()
);
create index reports_created_at_idx on public.reports (created_at desc);
alter table public.reports enable row level security;
-- No policies: written by the `ai` function, read in the dashboard.

-- Re-created functions keep server-only access.
revoke execute on function public.consume_quota(uuid, text, integer) from public, anon, authenticated;
revoke execute on function public.release_quota(uuid, text) from public, anon, authenticated;
revoke execute on function public.consume_device_quota(text, text, integer) from public, anon, authenticated;
revoke execute on function public.release_device_quota(text, text) from public, anon, authenticated;
revoke execute on function public.consume_sub_quota(text, text, integer) from public, anon, authenticated;
revoke execute on function public.release_sub_quota(text, text) from public, anon, authenticated;
grant execute on function public.consume_quota(uuid, text, integer) to service_role;
grant execute on function public.release_quota(uuid, text) to service_role;
grant execute on function public.consume_device_quota(text, text, integer) to service_role;
grant execute on function public.release_device_quota(text, text) to service_role;
grant execute on function public.consume_sub_quota(text, text, integer) to service_role;
grant execute on function public.release_sub_quota(text, text) to service_role;
