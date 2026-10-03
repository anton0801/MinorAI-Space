-- Keep the PRO check out of the exposed API and scoped to the caller only.
create schema if not exists private;
grant usage on schema private to authenticated;

create function private.caller_is_pro()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and plan = 'pro' and (plan_expires_at is null or plan_expires_at > now())
  );
$$;

revoke execute on function private.caller_is_pro() from public, anon;
grant execute on function private.caller_is_pro() to authenticated;

create policy "PRO users upload shared maps to their folder"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'shared'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and private.caller_is_pro()
  );

create policy "PRO users replace their shared maps"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'shared' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (
    bucket_id = 'shared'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and private.caller_is_pro()
  );
