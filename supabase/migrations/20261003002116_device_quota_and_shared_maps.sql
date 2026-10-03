-- Free-plan usage is also counted per device, so signing out (a fresh anonymous account)
-- does not reset the monthly allowance.
create table public.device_usage (
  device_id text not null,
  period text not null,
  maps integer not null default 0,
  expands integer not null default 0,
  chats integer not null default 0,
  primary key (device_id, period)
);

alter table public.device_usage enable row level security;
-- No policies: only the service role (edge functions) touches this table.

create function public.consume_device_quota(p_device text, p_kind text, p_limit integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
  v_used integer;
begin
  insert into public.device_usage (device_id, period) values (p_device, v_period)
    on conflict (device_id, period) do nothing;

  if p_kind = 'maps' then
    update public.device_usage set maps = maps + 1
      where device_id = p_device and period = v_period and maps < p_limit
      returning maps into v_used;
  elsif p_kind = 'expands' then
    update public.device_usage set expands = expands + 1
      where device_id = p_device and period = v_period and expands < p_limit
      returning expands into v_used;
  elsif p_kind = 'chats' then
    update public.device_usage set chats = chats + 1
      where device_id = p_device and period = v_period and chats < p_limit
      returning chats into v_used;
  else
    raise exception 'unknown quota kind %', p_kind;
  end if;

  if v_used is null then
    return -1;
  end if;
  return p_limit - v_used;
end;
$$;

create function public.release_device_quota(p_device text, p_kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
begin
  if p_kind = 'maps' then
    update public.device_usage set maps = greatest(maps - 1, 0) where device_id = p_device and period = v_period;
  elsif p_kind = 'expands' then
    update public.device_usage set expands = greatest(expands - 1, 0) where device_id = p_device and period = v_period;
  elsif p_kind = 'chats' then
    update public.device_usage set chats = greatest(chats - 1, 0) where device_id = p_device and period = v_period;
  end if;
end;
$$;

revoke execute on function public.consume_device_quota(text, text, integer) from public, anon, authenticated;
revoke execute on function public.release_device_quota(text, text) from public, anon, authenticated;
grant execute on function public.consume_device_quota(text, text, integer) to service_role;
grant execute on function public.release_device_quota(text, text) to service_role;

-- Share Link (PRO): a public bucket of map images, one folder per user.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('shared', 'shared', true, 10485760, array['image/png'])
on conflict (id) do nothing;

create policy "Users delete their shared maps"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'shared' and (storage.foldername(name))[1] = (select auth.uid())::text);
