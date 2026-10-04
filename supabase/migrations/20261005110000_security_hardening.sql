-- Security review, October 2026: caps so one account can't fill the database or storage,
-- a plan check when a map is first shared, a rule for moving subscriptions between accounts,
-- and table grants narrowed to what the app uses.

-- 1. Size caps. NOT VALID: what is stored stays; new and changed rows must fit.
alter table public.synced_maps drop constraint synced_maps_size;
alter table public.synced_maps add constraint synced_maps_size check (octet_length(data::text) <= 2000000) not valid;
alter table public.collab_maps drop constraint collab_maps_size;
alter table public.collab_maps add constraint collab_maps_size check (octet_length(data::text) <= 2000000) not valid;

-- 2. Synced maps and presentations: at most 200 MB per account, counted as rows change.
create table private.account_bytes (
  user_id uuid primary key references auth.users (id) on delete cascade,
  bytes bigint not null default 0
);
revoke all on private.account_bytes from public, anon, authenticated;

insert into private.account_bytes (user_id, bytes)
select user_id, sum(octet_length(data::text)) from public.synced_maps group by user_id
on conflict (user_id) do update set bytes = excluded.bytes;

create or replace function public.synced_maps_touch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delta bigint;
  v_total bigint;
begin
  new.server_updated_at := clock_timestamp();
  if tg_op = 'INSERT' and (select count(*) from public.synced_maps where user_id = new.user_id) >= 3000 then
    raise exception 'too many maps' using errcode = 'P0001';
  end if;
  v_delta := octet_length(new.data::text) - case when tg_op = 'UPDATE' then octet_length(old.data::text) else 0 end;
  insert into private.account_bytes as a (user_id, bytes) values (new.user_id, greatest(v_delta, 0))
    on conflict (user_id) do update set bytes = greatest(a.bytes + v_delta, 0)
    returning a.bytes into v_total;
  if v_delta > 0 and v_total > 200000000 then
    raise exception 'storage full' using errcode = 'MA003';
  end if;
  return new;
end;
$$;

create or replace function public.synced_maps_forget()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.account_bytes set bytes = greatest(bytes - octet_length(old.data::text), 0) where user_id = old.user_id;
  return old;
end;
$$;

create trigger synced_maps_forget
  after delete on public.synced_maps
  for each row execute function public.synced_maps_forget();

-- 3. Sharing a map needs Plus or PRO (the app checks too), and an owner has at most 100.
create or replace function public.collab_maps_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.collab_member_limit(public.active_plan(new.owner)) = 0 then
    raise exception 'plan required' using errcode = 'MA001';
  end if;
  if (select count(*) from public.collab_maps where owner = new.owner) >= 100 then
    raise exception 'too many shared maps' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger collab_maps_guard
  before insert on public.collab_maps
  for each row execute function public.collab_maps_guard();

-- 4. Pictures: at most 3000 per account and 500 per shared map.
create or replace function private.folder_count_ok(p_bucket text, p_folder text, p_max integer)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select count(*) < p_max from storage.objects o
  where o.bucket_id = p_bucket and (storage.foldername(o.name))[1] = p_folder;
$$;

drop policy "Own map images: add" on storage.objects;
create policy "Own map images: add" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'map-images'
              and (storage.foldername(name))[1] = (select auth.uid())::text
              and private.folder_count_ok('map-images', (select auth.uid())::text, 3000));

drop policy "Shared map images: add" on storage.objects;
create policy "Shared map images: add" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'collab-images'
              and public.can_edit_collab(((storage.foldername(name))[1])::uuid)
              and private.folder_count_ok('collab-images', (storage.foldername(name))[1], 500));

-- 5. When a subscription last moved to another account (see the `subscription` function).
alter table public.subscriptions add column owner_changed_at timestamptz;

-- 6. The app signs in for everything: nothing for anon, and server-only tables for no client.
revoke all on all tables in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;
revoke all on public.subscriptions, public.subscription_usage, public.device_usage, public.apple_tokens,
              public.reports, public.shared_links, public.collab_invites from authenticated;

revoke execute on function public.synced_maps_touch() from public, anon, authenticated;
revoke execute on function public.synced_maps_forget() from public, anon, authenticated;
revoke execute on function public.collab_maps_guard() from public, anon, authenticated;
revoke execute on function private.folder_count_ok(text, text, integer) from public, anon;
grant execute on function private.folder_count_ok(text, text, integer) to authenticated;
