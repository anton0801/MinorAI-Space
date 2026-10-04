-- AI presentations get their own monthly count, like maps and images.

alter table public.usage add column decks integer not null default 0;
alter table public.device_usage add column decks integer not null default 0;
alter table public.subscription_usage add column decks integer not null default 0;

-- The quota functions accept the new counter (column names come from this fixed list only).
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
  if p_kind not in ('maps', 'expands', 'chats', 'images', 'decks') then
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
  if p_kind not in ('maps', 'expands', 'chats', 'images', 'decks') then
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
  if p_kind not in ('maps', 'expands', 'chats', 'images', 'decks') then
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
  if p_kind not in ('maps', 'expands', 'chats', 'images', 'decks') then
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
  if p_kind not in ('maps', 'expands', 'chats', 'images', 'decks') then
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
  if p_kind not in ('maps', 'expands', 'chats', 'images', 'decks') then
    return;
  end if;
  execute format(
    'update public.subscription_usage set %1$I = greatest(%1$I - 1, 0) where original_transaction_id = $1 and period = $2', p_kind
  ) using p_sub, v_period;
end;
$$;

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

-- Presentations sync like maps: the same table, told apart by `kind`.
alter table public.synced_maps add column kind text not null default 'map';
alter table public.synced_maps add constraint synced_maps_kind check (kind in ('map', 'deck'));
