-- Maps synced between a person's devices. Each row is one map as the app stores it (JSON);
-- the app merges by `updated_at` (newest edit wins) and pulls by `server_updated_at`.
-- Deleted maps stay as small tombstones so other devices learn about the delete.

create table public.synced_maps (
  user_id uuid not null references auth.users (id) on delete cascade,
  id uuid not null,
  data jsonb not null,
  updated_at timestamptz not null,
  deleted boolean not null default false,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id),
  constraint synced_maps_size check (octet_length(data::text) <= 4000000)
);

create index synced_maps_pull_idx on public.synced_maps (user_id, server_updated_at);

alter table public.synced_maps enable row level security;

create policy "Own maps: read" on public.synced_maps
  for select to authenticated using (user_id = (select auth.uid()));
create policy "Own maps: add" on public.synced_maps
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Own maps: change" on public.synced_maps
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Own maps: remove" on public.synced_maps
  for delete to authenticated using (user_id = (select auth.uid()));

grant select, insert, update, delete on public.synced_maps to authenticated;

-- The pull cursor always moves forward, whatever time the device sends; and one account keeps
-- at most 3000 maps (tombstones included).
create or replace function public.synced_maps_touch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.server_updated_at := clock_timestamp();
  if tg_op = 'INSERT' and (select count(*) from public.synced_maps where user_id = new.user_id) >= 3000 then
    raise exception 'too many maps' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger synced_maps_touch
  before insert or update on public.synced_maps
  for each row execute function public.synced_maps_touch();

revoke execute on function public.synced_maps_touch() from public, anon, authenticated;

-- Pictures on synced maps: private, one folder per person ("<user id>/<image id>.jpg").
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('map-images', 'map-images', false, 4194304, array['image/jpeg'])
on conflict (id) do nothing;

create policy "Own map images: read" on storage.objects
  for select to authenticated
  using (bucket_id = 'map-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Own map images: add" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'map-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Own map images: change" on storage.objects
  for update to authenticated
  using (bucket_id = 'map-images' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'map-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Own map images: remove" on storage.objects
  for delete to authenticated
  using (bucket_id = 'map-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
