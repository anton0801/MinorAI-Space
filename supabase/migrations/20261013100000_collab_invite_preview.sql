-- What an invite link offers, shown before anyone joins: the map's title, the role it gives,
-- the inviter's name when the account has one, and whether it can still be used. Nothing of the
-- map's content is returned, and opening the preview adds no one. Works before sign-in too: the
-- link's secret is the permission to see this much.

create or replace function public.collab_invite_preview(p_token text)
returns table (map_id uuid, title text, role text, inviter text, status text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_map uuid;
  v_role text;
  v_by uuid;
  v_owner uuid;
begin
  if p_token is null or length(p_token) < 16 or length(p_token) > 128 then
    return query select null::uuid, null::text, null::text, null::text, 'invalid'::text;
    return;
  end if;
  select i.map_id, i.role, i.created_by into v_map, v_role, v_by from public.collab_invites i
   where i.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') and i.expires_at > now();
  if v_map is null then
    return query select null::uuid, null::text, null::text, null::text, 'invalid'::text;
    return;
  end if;
  select m.owner into v_owner from public.collab_maps m where m.id = v_map;
  if v_owner is null then
    return query select null::uuid, null::text, null::text, null::text, 'invalid'::text;
    return;
  end if;
  return query
    select v_map,
           left(coalesce(m.data -> 'root' ->> 'title', ''), 120),
           v_role,
           nullif(left(trim(coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name', '')), 60), ''),
           case
             when v_user is not null and (v_owner = v_user or exists (
               select 1 from public.collab_members c where c.map_id = v_map and c.user_id = v_user)) then 'member'
             when (select count(*) from public.collab_members c where c.map_id = v_map)
                  >= public.collab_member_limit(public.active_plan(v_owner)) then 'full'
             else 'ok'
           end
    from public.collab_maps m
    left join auth.users u on u.id = v_by
    where m.id = v_map;
end;
$$;

revoke execute on function public.collab_invite_preview(text) from public;
grant execute on function public.collab_invite_preview(text) to anon, authenticated;
