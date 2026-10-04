-- Maps edited together. The owner shares a map; people who open an invite link become editors.
-- The map lives in `collab_maps` (one row, with a version that goes up on every change), so
-- each device pulls the newest version and merges its own edits before pushing.

create table public.collab_maps (
  id uuid primary key,                         -- the map's own id
  owner uuid not null references auth.users (id) on delete cascade,
  data jsonb not null,
  version integer not null default 1,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  constraint collab_maps_size check (octet_length(data::text) <= 4000000)
);

create table public.collab_members (
  map_id uuid not null references public.collab_maps (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (map_id, user_id)
);
create index collab_members_user_idx on public.collab_members (user_id);

-- Invite links keep only a hash of their secret.
create table public.collab_invites (
  token_hash text primary key,
  map_id uuid not null references public.collab_maps (id) on delete cascade,
  created_by uuid not null references auth.users (id) on delete cascade,
  expires_at timestamptz not null default now() + interval '14 days'
);

-- Whether the signed-in person may open a shared map (owner or member).
create or replace function public.can_edit_collab(p_map uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.collab_maps m where m.id = p_map and m.owner = (select auth.uid()))
      or exists (select 1 from public.collab_members c where c.map_id = p_map and c.user_id = (select auth.uid()));
$$;

alter table public.collab_maps enable row level security;
alter table public.collab_members enable row level security;
alter table public.collab_invites enable row level security;

create policy "Shared maps: read" on public.collab_maps
  for select to authenticated using (public.can_edit_collab(id));
create policy "Shared maps: share own" on public.collab_maps
  for insert to authenticated with check (owner = (select auth.uid()));
create policy "Shared maps: edit" on public.collab_maps
  for update to authenticated using (public.can_edit_collab(id)) with check (public.can_edit_collab(id));
create policy "Shared maps: stop sharing" on public.collab_maps
  for delete to authenticated using (owner = (select auth.uid()));

create policy "Members: see" on public.collab_members
  for select to authenticated
  using (user_id = (select auth.uid()) or exists (select 1 from public.collab_maps m where m.id = map_id and m.owner = (select auth.uid())));
create policy "Members: leave or remove" on public.collab_members
  for delete to authenticated
  using (user_id = (select auth.uid()) or exists (select 1 from public.collab_maps m where m.id = map_id and m.owner = (select auth.uid())));
-- No direct inserts: joining goes through join_collab_map.

grant select, insert, update, delete on public.collab_maps to authenticated;
grant select, delete on public.collab_members to authenticated;

-- The version only moves forward, and the server records who changed the map and when.
create or replace function public.collab_maps_touch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.owner <> old.owner or new.id <> old.id then
      raise exception 'owner and id cannot change' using errcode = 'P0001';
    end if;
    new.version := old.version + 1;
  end if;
  new.updated_by := (select auth.uid());
  new.updated_at := now();
  return new;
end;
$$;

create trigger collab_maps_touch
  before insert or update on public.collab_maps
  for each row execute function public.collab_maps_touch();

-- The owner (or a member) makes an invite link; the secret is returned once.
create or replace function public.create_collab_invite(p_map uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
begin
  if not exists (select 1 from public.collab_maps m where m.id = p_map and m.owner = (select auth.uid())) then
    raise exception 'not the owner' using errcode = '42501';
  end if;
  v_token := translate(encode(extensions.gen_random_bytes(24), 'base64'), '+/=', '-_');
  insert into public.collab_invites (token_hash, map_id, created_by)
  values (encode(extensions.digest(v_token, 'sha256'), 'hex'), p_map, (select auth.uid()));
  return v_token;
end;
$$;

-- Opening an invite link: the person becomes an editor of the map. Returns the map's id.
create or replace function public.join_collab_map(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_map uuid;
  v_user uuid := (select auth.uid());
begin
  if v_user is null or coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  select i.map_id into v_map from public.collab_invites i
   where i.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') and i.expires_at > now();
  if v_map is null then
    raise exception 'invalid invite' using errcode = 'P0002';
  end if;
  if (select count(*) from public.collab_members where map_id = v_map) >= 50 then
    raise exception 'too many members' using errcode = 'P0001';
  end if;
  insert into public.collab_members (map_id, user_id) values (v_map, v_user)
    on conflict do nothing;
  return v_map;
end;
$$;

revoke execute on function public.collab_maps_touch() from public, anon, authenticated;
revoke execute on function public.create_collab_invite(uuid) from public, anon;
revoke execute on function public.join_collab_map(text) from public, anon;
revoke execute on function public.can_edit_collab(uuid) from public, anon;
grant execute on function public.create_collab_invite(uuid) to authenticated;
grant execute on function public.join_collab_map(text) to authenticated;
grant execute on function public.can_edit_collab(uuid) to authenticated;

-- Pictures of shared maps: "<map id>/<image id>.jpg", readable and writable by its editors.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('collab-images', 'collab-images', false, 4194304, array['image/jpeg'])
on conflict (id) do nothing;

create policy "Shared map images: read" on storage.objects
  for select to authenticated
  using (bucket_id = 'collab-images' and public.can_edit_collab(((storage.foldername(name))[1])::uuid));
create policy "Shared map images: add" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'collab-images' and public.can_edit_collab(((storage.foldername(name))[1])::uuid));
create policy "Shared map images: change" on storage.objects
  for update to authenticated
  using (bucket_id = 'collab-images' and public.can_edit_collab(((storage.foldername(name))[1])::uuid));
