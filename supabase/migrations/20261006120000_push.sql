-- Remote notifications (Apple Push Notification service): the devices of each person, what they
-- want to hear about, and a throttle so a busy shared map doesn't ring every minute.

create table public.push_tokens (
  token text primary key check (token ~ '^[0-9a-f]{64,200}$'),
  user_id uuid not null references auth.users (id) on delete cascade,
  sandbox boolean not null default false,          -- a development build (APNs sandbox)
  language text not null default 'en' check (language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$'),
  collab boolean not null default true,            -- changes and people in shared maps
  account boolean not null default true,           -- invitations, rewards, limits
  updated_at timestamptz not null default now()
);
create index push_tokens_user on public.push_tokens (user_id);

create table public.push_log (
  user_id uuid not null references auth.users (id) on delete cascade,
  topic text not null,
  sent_at timestamptz not null default now(),
  primary key (user_id, topic)
);

alter table public.push_tokens enable row level security;
alter table public.push_log enable row level security;
revoke all on public.push_tokens, public.push_log from public, anon, authenticated;

-- The app registers its device token for the signed-in person. A token that belonged to another
-- account on this device moves over; each person keeps their 10 most recent devices.
create function public.register_push_token(p_token text, p_sandbox boolean, p_language text, p_collab boolean, p_account boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'sign_in_required' using errcode = 'P0001';
  end if;
  insert into public.push_tokens (token, user_id, sandbox, language, collab, account, updated_at)
    values (lower(p_token), v_user, coalesce(p_sandbox, false), coalesce(p_language, 'en'), coalesce(p_collab, true), coalesce(p_account, true), now())
    on conflict (token) do update set
      user_id = excluded.user_id,
      sandbox = excluded.sandbox,
      language = excluded.language,
      collab = excluded.collab,
      account = excluded.account,
      updated_at = now();
  delete from public.push_tokens
    where user_id = v_user
      and token not in (select token from public.push_tokens where user_id = v_user order by updated_at desc limit 10);
end;
$$;

-- On sign-out: this device stops getting the person's notifications.
create function public.unregister_push_token(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.push_tokens where token = lower(p_token) and user_id = auth.uid();
$$;

-- True when a notification on this topic may go to this person now (none in the last p_seconds);
-- records it in the same step, so parallel requests can't both pass.
create function public.push_allowed(p_user uuid, p_topic text, p_seconds integer)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.push_log (user_id, topic, sent_at) values (p_user, p_topic, now())
    on conflict (user_id, topic) do update set sent_at = now()
    where public.push_log.sent_at < now() - make_interval(secs => p_seconds);
  return found;
end;
$$;

revoke execute on function public.register_push_token(text, boolean, text, boolean, boolean) from public, anon;
revoke execute on function public.unregister_push_token(text) from public, anon;
revoke execute on function public.push_allowed(uuid, text, integer) from public, anon, authenticated;
grant execute on function public.register_push_token(text, boolean, text, boolean, boolean) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;
grant execute on function public.push_allowed(uuid, text, integer) to service_role;
