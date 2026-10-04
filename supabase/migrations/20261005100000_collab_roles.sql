-- Roles in shared maps: editors change the map, viewers only see it. The owner manages people.
-- How many can join depends on the owner's plan (Plus 5, PRO 25); people who join need no plan.
-- Inviting is checked here, not only in the app.

alter table public.collab_members
  add column role text not null default 'editor' check (role in ('editor', 'viewer'));
alter table public.collab_invites
  add column role text not null default 'editor' check (role in ('editor', 'viewer')),
  add column created_at timestamptz not null default now();

-- The plan a person has right now (an expired subscription counts as free).
create or replace function public.active_plan(p_user uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case when p.plan <> 'free' and (p.plan_expires_at is null or p.plan_expires_at > now()) then p.plan else 'free' end
    from public.profiles p where p.id = p_user
  ), 'free');
$$;

create or replace function public.collab_member_limit(p_plan text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_plan when 'pro' then 25 when 'plus' then 5 else 0 end;
$$;

-- Owner or any member may open a shared map.
create or replace function public.can_view_collab(p_map uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.collab_maps m where m.id = p_map and m.owner = (select auth.uid()))
      or exists (select 1 from public.collab_members c where c.map_id = p_map and c.user_id = (select auth.uid()));
$$;

-- Only the owner and editors may change it.
create or replace function public.can_edit_collab(p_map uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.collab_maps m where m.id = p_map and m.owner = (select auth.uid()))
      or exists (select 1 from public.collab_members c where c.map_id = p_map and c.user_id = (select auth.uid()) and c.role = 'editor');
$$;

drop policy "Shared maps: read" on public.collab_maps;
create policy "Shared maps: read" on public.collab_maps
  for select to authenticated using (public.can_view_collab(id));
-- "Shared maps: edit" already uses can_edit_collab, which now leaves viewers out.

drop policy "Shared map images: read" on storage.objects;
create policy "Shared map images: read" on storage.objects
  for select to authenticated
  using (bucket_id = 'collab-images' and public.can_view_collab(((storage.foldername(name))[1])::uuid));

-- Members see each other's role (the list itself comes from collab_member_list).
drop policy "Members: see" on public.collab_members;
create policy "Members: see" on public.collab_members
  for select to authenticated using (public.can_view_collab(map_id));

-- A new invite link. Only the owner, and only with Plus or PRO.
drop function public.create_collab_invite(uuid);
create function public.create_collab_invite(p_map uuid, p_role text default 'editor')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_token text;
begin
  if p_role not in ('editor', 'viewer') then
    raise exception 'bad role' using errcode = '22023';
  end if;
  if not exists (select 1 from public.collab_maps m where m.id = p_map and m.owner = v_user) then
    raise exception 'not the owner' using errcode = '42501';
  end if;
  if public.collab_member_limit(public.active_plan(v_user)) = 0 then
    raise exception 'plan required' using errcode = 'MA001';
  end if;
  -- Old and surplus links go: at most 20 live links per map.
  delete from public.collab_invites i where i.map_id = p_map and i.expires_at <= now();
  delete from public.collab_invites i where i.token_hash in (
    select token_hash from public.collab_invites where map_id = p_map order by created_at desc offset 19
  );
  v_token := translate(encode(extensions.gen_random_bytes(24), 'base64'), '+/=', '-_');
  insert into public.collab_invites (token_hash, map_id, created_by, role)
  values (encode(extensions.digest(v_token, 'sha256'), 'hex'), p_map, v_user, p_role);
  return v_token;
end;
$$;

-- Opening an invite link. The role comes from the link; people already in keep theirs.
create or replace function public.join_collab_map(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_map uuid;
  v_role text;
  v_owner uuid;
  v_user uuid := (select auth.uid());
begin
  if v_user is null or coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  select i.map_id, i.role into v_map, v_role from public.collab_invites i
   where i.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') and i.expires_at > now();
  if v_map is null then
    raise exception 'invalid invite' using errcode = 'P0002';
  end if;
  -- One join at a time per map, so parallel joins can't pass the limit together.
  select m.owner into v_owner from public.collab_maps m where m.id = v_map for update;
  if v_owner = v_user or exists (select 1 from public.collab_members c where c.map_id = v_map and c.user_id = v_user) then
    return v_map;
  end if;
  if (select count(*) from public.collab_members c where c.map_id = v_map) >= public.collab_member_limit(public.active_plan(v_owner)) then
    raise exception 'map is full' using errcode = 'MA002';
  end if;
  insert into public.collab_members (map_id, user_id, role) values (v_map, v_user, v_role)
    on conflict do nothing;
  return v_map;
end;
$$;

-- Everyone on a shared map, owner first. The owner sees addresses in full; others see their own
-- and the owner's, and a shortened form of the rest.
create or replace function public.collab_member_list(p_map uuid)
returns table (user_id uuid, email text, role text, joined_at timestamptz, member_limit integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_owner uuid;
begin
  if not public.can_view_collab(p_map) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select m.owner into v_owner from public.collab_maps m where m.id = p_map;
  return query
    select x.user_id,
           case when v_user = v_owner or x.user_id in (v_user, v_owner) then x.email
                else left(split_part(x.email, '@', 1), 2) || '•••@' || split_part(x.email, '@', 2) end,
           x.role, x.joined_at,
           public.collab_member_limit(public.active_plan(v_owner))
    from (
      select v_owner as user_id, u.email::text as email, 'owner'::text as role, null::timestamptz as joined_at, 0 as sort
        from auth.users u where u.id = v_owner
      union all
      select c.user_id, u.email::text, c.role, c.joined_at, 1
        from public.collab_members c join auth.users u on u.id = c.user_id
        where c.map_id = p_map
    ) x
    order by x.sort, x.joined_at;
end;
$$;

-- The owner changes someone's role.
create or replace function public.set_collab_role(p_map uuid, p_user uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_role not in ('editor', 'viewer') then
    raise exception 'bad role' using errcode = '22023';
  end if;
  if not exists (select 1 from public.collab_maps m where m.id = p_map and m.owner = (select auth.uid())) then
    raise exception 'not the owner' using errcode = '42501';
  end if;
  update public.collab_members set role = p_role where map_id = p_map and user_id = p_user;
end;
$$;

-- The owner removes someone. Invite links are turned off too, so an old link can't bring them
-- back; the owner sends a new link to anyone else they want to invite.
create or replace function public.remove_collab_member(p_map uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.collab_maps m where m.id = p_map and m.owner = (select auth.uid())) then
    raise exception 'not the owner' using errcode = '42501';
  end if;
  delete from public.collab_members where map_id = p_map and user_id = p_user;
  delete from public.collab_invites where map_id = p_map;
end;
$$;

-- The owner turns off every invite link of a map (people already in stay).
create or replace function public.revoke_collab_invites(p_map uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.collab_maps m where m.id = p_map and m.owner = (select auth.uid())) then
    raise exception 'not the owner' using errcode = '42501';
  end if;
  delete from public.collab_invites where map_id = p_map;
end;
$$;

revoke execute on function public.active_plan(uuid) from public, anon, authenticated;
revoke execute on function public.collab_member_limit(text) from public, anon;
revoke execute on function public.can_view_collab(uuid) from public, anon;
revoke execute on function public.create_collab_invite(uuid, text) from public, anon;
revoke execute on function public.join_collab_map(text) from public, anon;
revoke execute on function public.collab_member_list(uuid) from public, anon;
revoke execute on function public.set_collab_role(uuid, uuid, text) from public, anon;
revoke execute on function public.revoke_collab_invites(uuid) from public, anon;
revoke execute on function public.remove_collab_member(uuid, uuid) from public, anon;
grant execute on function public.remove_collab_member(uuid, uuid) to authenticated;
grant execute on function public.collab_member_limit(text) to authenticated;
grant execute on function public.can_view_collab(uuid) to authenticated;
grant execute on function public.create_collab_invite(uuid, text) to authenticated;
grant execute on function public.join_collab_map(text) to authenticated;
grant execute on function public.collab_member_list(uuid) to authenticated;
grant execute on function public.set_collab_role(uuid, uuid, text) to authenticated;
grant execute on function public.revoke_collab_invites(uuid) to authenticated;
