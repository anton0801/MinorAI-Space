-- Fixes from the pre-release audit (October 2026).

-- 1. Storage accounting for synced maps. The app pushes with an upsert (INSERT … ON CONFLICT DO
-- UPDATE), which runs the BEFORE INSERT trigger and then the BEFORE UPDATE trigger, so counting
-- there added the whole map again on every push until sync stopped with "storage full". Bytes and
-- the row cap are now counted in AFTER triggers, which fire only for what actually happened, and
-- the totals are recounted. Deleted maps (tombstones) no longer count toward the 3000 maps.
create or replace function public.synced_maps_touch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.server_updated_at := clock_timestamp();
  return new;
end;
$$;

create or replace function public.synced_maps_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delta bigint;
  v_total bigint;
begin
  if tg_op = 'INSERT' and not new.deleted
     and (select count(*) from public.synced_maps where user_id = new.user_id and not deleted) > 3000 then
    raise exception 'too many maps' using errcode = 'P0001';
  end if;
  v_delta := octet_length(new.data::text) - case when tg_op = 'UPDATE' then octet_length(old.data::text) else 0 end;
  insert into private.account_bytes as a (user_id, bytes) values (new.user_id, greatest(v_delta, 0))
    on conflict (user_id) do update set bytes = greatest(a.bytes + v_delta, 0)
    returning a.bytes into v_total;
  if v_delta > 0 and v_total > 200000000 then
    raise exception 'storage full' using errcode = 'MA003';
  end if;
  return null;
end;
$$;

create trigger synced_maps_count
  after insert or update on public.synced_maps
  for each row execute function public.synced_maps_count();

update private.account_bytes a
  set bytes = coalesce((select sum(octet_length(m.data::text)) from public.synced_maps m where m.user_id = a.user_id), 0);

revoke execute on function public.synced_maps_count() from public, anon, authenticated;

-- 2. Picture caps: count a folder by name prefix (uses the bucket/name index instead of reading
-- every object in the bucket on each upload).
create or replace function private.folder_count_ok(p_bucket text, p_folder text, p_max integer)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select count(*) < p_max from storage.objects o
  where o.bucket_id = p_bucket
    and o.name like replace(replace(replace(p_folder, '\', '\\'), '%', '\%'), '_', '\_') || '/%';
$$;

-- 3. Invitations: "at most 3 friends per code" counts every redemption ever, so deleting a
-- friend's account doesn't free a place.
alter table public.referral_codes add column redeemed integer not null default 0;
update public.referral_codes c set redeemed = (select count(*) from public.referrals r where r.inviter = c.user_id);

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
  update public.referral_codes set redeemed = redeemed + 1 where user_id = v_inviter and redeemed < 3;
  if not found then
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

-- 4. Shared maps: once a map stops being shared, its id stays with its owner, so a former member
-- can't share a map with the same id and become the owner of its old pictures.
create table private.retired_collab_maps (
  id uuid primary key,
  owner uuid not null,
  retired_at timestamptz not null default now()
);
revoke all on private.retired_collab_maps from public, anon, authenticated;

create or replace function public.collab_maps_retire()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into private.retired_collab_maps (id, owner) values (old.id, old.owner)
    on conflict (id) do update set owner = excluded.owner, retired_at = now();
  return old;
end;
$$;

create trigger collab_maps_retire
  after delete on public.collab_maps
  for each row execute function public.collab_maps_retire();

create or replace function public.collab_maps_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from private.retired_collab_maps r where r.id = new.id and r.owner <> new.owner) then
    raise exception 'map id taken' using errcode = 'P0001';
  end if;
  if public.collab_member_limit(public.active_plan(new.owner)) = 0 then
    raise exception 'plan required' using errcode = 'MA001';
  end if;
  if (select count(*) from public.collab_maps where owner = new.owner) >= 100 then
    raise exception 'too many shared maps' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.collab_maps_retire() from public, anon, authenticated;
revoke execute on function public.collab_maps_guard() from public, anon, authenticated;
