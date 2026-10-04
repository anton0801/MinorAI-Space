-- What the monthly AI allowance went to: maps (with everything done on a map), presentations,
-- the assistant and pictures. Shown in the app as a breakdown of the allowance.

alter table public.usage
  add column spend_maps bigint not null default 0,
  add column spend_decks bigint not null default 0,
  add column spend_chat bigint not null default 0,
  add column spend_images bigint not null default 0;

alter table public.subscription_usage
  add column spend_maps bigint not null default 0,
  add column spend_decks bigint not null default 0,
  add column spend_chat bigint not null default 0,
  add column spend_images bigint not null default 0;

-- Like reserve_spend, and books the amount to an area too. Returns the new monthly total, or -1
-- when a positive amount doesn't fit under the limit (nothing is booked then), so the server can
-- tell when someone passes a share of the allowance.
create function public.reserve_spend_area(p_user uuid, p_sub text, p_amount bigint, p_limit bigint, p_area text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYY-MM');
  v_area text := case when p_area in ('maps', 'decks', 'chat', 'images') then p_area end;
  v_total bigint;
begin
  if p_sub is not null then
    insert into public.subscription_usage (original_transaction_id, period) values (p_sub, v_period)
      on conflict (original_transaction_id, period) do nothing;
    update public.subscription_usage set
      spend_micros = greatest(spend_micros + p_amount, 0),
      spend_maps = case when v_area = 'maps' then greatest(spend_maps + p_amount, 0) else spend_maps end,
      spend_decks = case when v_area = 'decks' then greatest(spend_decks + p_amount, 0) else spend_decks end,
      spend_chat = case when v_area = 'chat' then greatest(spend_chat + p_amount, 0) else spend_chat end,
      spend_images = case when v_area = 'images' then greatest(spend_images + p_amount, 0) else spend_images end
    where original_transaction_id = p_sub and period = v_period
      and (p_amount <= 0 or spend_micros + p_amount <= p_limit)
    returning spend_micros into v_total;
    return coalesce(v_total, -1);
  end if;

  insert into public.usage (user_id, period) values (p_user, v_period)
    on conflict (user_id, period) do nothing;
  update public.usage set
    spend_micros = greatest(spend_micros + p_amount, 0),
    spend_maps = case when v_area = 'maps' then greatest(spend_maps + p_amount, 0) else spend_maps end,
    spend_decks = case when v_area = 'decks' then greatest(spend_decks + p_amount, 0) else spend_decks end,
    spend_chat = case when v_area = 'chat' then greatest(spend_chat + p_amount, 0) else spend_chat end,
    spend_images = case when v_area = 'images' then greatest(spend_images + p_amount, 0) else spend_images end
  where user_id = p_user and period = v_period
    and (p_amount <= 0 or spend_micros + p_amount <= p_limit)
  returning spend_micros into v_total;
  return coalesce(v_total, -1);
end;
$$;

revoke execute on function public.reserve_spend_area(uuid, text, bigint, bigint, text) from public, anon, authenticated;
grant execute on function public.reserve_spend_area(uuid, text, bigint, bigint, text) to service_role;
