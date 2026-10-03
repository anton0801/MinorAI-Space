-- One row per App Store subscription (originalTransactionId). The latest verified presenter owns it,
-- refunds and revocations stick, and notifications are applied in order.
create table public.subscriptions (
  original_transaction_id text primary key,
  user_id uuid references auth.users (id) on delete set null,
  product_id text not null,
  plan text not null check (plan in ('plus', 'pro')),
  expires_at timestamptz,
  environment text not null,
  revoked boolean not null default false,
  last_signed_at timestamptz not null,
  updated_at timestamptz not null default now()
);
create index subscriptions_user_id_idx on public.subscriptions (user_id);
alter table public.subscriptions enable row level security;
-- No policies: only edge functions (service role) read or write subscriptions.

-- The best active plan for a user, written to profiles for the app to read.
create function public.recompute_plan(p_user uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan text;
  v_expires timestamptz;
begin
  select s.plan, s.expires_at into v_plan, v_expires
  from public.subscriptions s
  where s.user_id = p_user and not s.revoked and s.expires_at > now()
  order by (s.plan = 'pro') desc, s.expires_at desc
  limit 1;

  insert into public.profiles (id) values (p_user) on conflict (id) do nothing;
  update public.profiles
    set plan = coalesce(v_plan, 'free'), plan_expires_at = v_expires, updated_at = now()
    where id = p_user;
  return coalesce(v_plan, 'free');
end;
$$;

-- Token spend per month, for a fair-use budget on top of request counts.
alter table public.usage add column tokens bigint not null default 0;

create function public.add_tokens(p_user uuid, p_tokens integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
begin
  insert into public.usage (user_id, period, tokens) values (p_user, v_period, greatest(p_tokens, 0))
    on conflict (user_id, period) do update set tokens = public.usage.tokens + greatest(p_tokens, 0);
end;
$$;

-- Share Link images are uploaded by the `share` function under random names.
create table public.shared_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  map_id text not null,
  path text not null unique,
  created_at timestamptz not null default now(),
  unique (user_id, map_id)
);
alter table public.shared_links enable row level security;

-- Sign in with Apple refresh tokens, kept only to revoke them when the account is deleted.
create table public.apple_tokens (
  user_id uuid primary key references auth.users (id) on delete cascade,
  refresh_token text not null,
  created_at timestamptz not null default now()
);
alter table public.apple_tokens enable row level security;

-- Clients no longer write to storage directly.
drop policy if exists "PRO users upload shared maps to their folder" on storage.objects;
drop policy if exists "PRO users replace their shared maps" on storage.objects;
drop policy if exists "Users read their shared maps" on storage.objects;
drop policy if exists "Users delete their shared maps" on storage.objects;
drop function if exists private.caller_is_pro();

revoke execute on function public.recompute_plan(uuid) from public, anon, authenticated;
revoke execute on function public.add_tokens(uuid, integer) from public, anon, authenticated;
grant execute on function public.recompute_plan(uuid) to service_role;
grant execute on function public.add_tokens(uuid, integer) to service_role;
