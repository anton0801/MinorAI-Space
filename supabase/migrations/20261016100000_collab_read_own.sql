-- Sharing a map inserts its row and reads it back (Prefer: return=representation). The read
-- policy only asked can_view_collab(), which looks the map up in a snapshot taken before the
-- insert, so the owner's own new row failed it and every first share was refused (403, "new row
-- violates row-level security policy"). The owner is now checked on the row itself.
drop policy "Shared maps: read" on public.collab_maps;
create policy "Shared maps: read" on public.collab_maps
  for select to authenticated using (owner = (select auth.uid()) or public.can_view_collab(id));
