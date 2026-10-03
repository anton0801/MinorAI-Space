-- Upserting a shared map image needs read access to the user's own folder.
create policy "Users read their shared maps"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'shared' and (storage.foldername(name))[1] = (select auth.uid())::text);
