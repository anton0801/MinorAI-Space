-- Profiles: one row per auth user, holds the subscription plan.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  plan text not null default 'free' check (plan in ('free', 'plus', 'pro')),
  plan_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users can read their own profile"
  on public.profiles for select
  to authenticated
  using ((select auth.uid()) = id);

-- Usage: AI calls counted per user per calendar month (UTC), used for free-tier limits.
create table public.usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  period text not null,
  maps integer not null default 0,
  expands integer not null default 0,
  chats integer not null default 0,
  primary key (user_id, period)
);

alter table public.usage enable row level security;

create policy "Users can read their own usage"
  on public.usage for select
  to authenticated
  using ((select auth.uid()) = user_id);

-- Create a profile for every new auth user (Apple or anonymous).
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Atomically take one unit of quota. Returns how many are left, or -1 when the limit is reached.
create function public.consume_quota(p_user uuid, p_kind text, p_limit integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
  v_used integer;
begin
  insert into public.usage (user_id, period) values (p_user, v_period)
    on conflict (user_id, period) do nothing;

  if p_kind = 'maps' then
    update public.usage set maps = maps + 1
      where user_id = p_user and period = v_period and maps < p_limit
      returning maps into v_used;
  elsif p_kind = 'expands' then
    update public.usage set expands = expands + 1
      where user_id = p_user and period = v_period and expands < p_limit
      returning expands into v_used;
  elsif p_kind = 'chats' then
    update public.usage set chats = chats + 1
      where user_id = p_user and period = v_period and chats < p_limit
      returning chats into v_used;
  else
    raise exception 'unknown quota kind %', p_kind;
  end if;

  if v_used is null then
    return -1;
  end if;
  return p_limit - v_used;
end;
$$;

-- Give a unit back when the AI call fails after the quota was taken.
create function public.release_quota(p_user uuid, p_kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
begin
  if p_kind = 'maps' then
    update public.usage set maps = greatest(maps - 1, 0) where user_id = p_user and period = v_period;
  elsif p_kind = 'expands' then
    update public.usage set expands = greatest(expands - 1, 0) where user_id = p_user and period = v_period;
  elsif p_kind = 'chats' then
    update public.usage set chats = greatest(chats - 1, 0) where user_id = p_user and period = v_period;
  end if;
end;
$$;

-- Only the server (edge functions with the service role) may move quota.
revoke execute on function public.consume_quota(uuid, text, integer) from public, anon, authenticated;
revoke execute on function public.release_quota(uuid, text) from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
grant execute on function public.consume_quota(uuid, text, integer) to service_role;
grant execute on function public.release_quota(uuid, text) to service_role;
