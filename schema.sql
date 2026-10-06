-- =====================================================================
-- Stick2XU: run this whole file in Supabase → SQL Editor.
-- It's safe to run again after updates; it only adds what's missing.
-- Then add the admin's email at the bottom (see STEP AT THE END).
-- =====================================================================

create extension if not exists pgcrypto;

-- Shop settings (one row). Change prices here, no code edits needed.
create table if not exists public.shop_settings (
  id int primary key default 1 check (id = 1),
  price_per_sheet int not null default 50,   -- old, not used anymore: prices are in products below
  max_sheets int not null default 10,
  max_noshows int not null default 2
);
alter table public.shop_settings add column if not exists signal_verb text not null default 'holding';
alter table public.shop_settings add column if not exists signal_item text not null default 'a Stick2XU sign';
alter table public.shop_settings add column if not exists products jsonb not null default '{
  "stickers":  {"enabled": true,  "sizes": [{"id": "a4", "price": 50, "enabled": true}],
                "addons": [{"id": "inkjet", "label": "Inkjet print", "note": "brighter, more vivid colors", "price": 30, "enabled": true}]},
  "pins":      {"enabled": false, "sizes": [{"id": "58", "price": 35, "enabled": true}, {"id": "44", "price": 25, "enabled": true}], "addons": []},
  "posters":   {"enabled": false, "sizes": [{"id": "a4", "price": 40, "enabled": true}, {"id": "a3", "price": 80, "enabled": true}], "addons": []},
  "keychains": {"enabled": false, "sizes": [{"id": "std", "price": 45, "enabled": true}], "addons": []}
}'::jsonb;
alter table public.shop_settings add column if not exists deals jsonb not null default '[
  {"id": "d_stk3", "type": "bulk",    "product": "stickers", "min": 3, "off": 5, "enabled": false, "label": "3+ sheets: ₱5 off each"},
  {"id": "d_pin5", "type": "freebie", "product": "pins", "buy": 5, "free": 1, "enabled": false, "label": "Buy 5 pins, get 1 free"},
  {"id": "d_combo", "type": "combo",  "products": ["stickers", "keychains"], "off": 10, "enabled": false, "label": "Stickers + keychain combo: ₱10 off"}
]'::jsonb;
insert into public.shop_settings (id) values (1) on conflict do nothing;
-- Raise the old 3-sheet limit (only if it was never changed). Change it anytime in admin → Settings.
update public.shop_settings set max_sheets = 10 where id = 1 and max_sheets = 3;
-- Add the class pack deal for pins once (it stays off until pins are switched on)
update public.shop_settings set deals = deals || '[{"id": "d_class", "type": "tiers", "product": "pins", "enabled": true,
  "tiers": [{"min": 10, "off": 3}, {"min": 20, "off": 5}, {"min": 30, "off": 8}, {"min": 40, "off": 10}],
  "label": "Class pack: up to ₱10 off each pin"}]'::jsonb
where id = 1 and not exists (select 1 from jsonb_array_elements(deals) d where d->>'id' = 'd_class');

-- Who can open the admin page
create table if not exists public.admins (email text primary key);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  nickname text not null,
  grade_section text not null,
  pickup text not null,
  pickup_date date,
  pickup_time text,
  arrived_at timestamptz,
  payment text not null check (payment in ('cash','gcash')),
  gcash_ref text,
  layout jsonb not null,
  folder text not null,
  sheet_count int not null,
  total int not null,
  status text not null default 'pending'
    check (status in ('pending','approved','printing','ready','done','rejected','cancelled','noshow')),
  reject_reason text,
  confirmed boolean not null default false,
  paid boolean not null default false,
  src text,
  images_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Already ran an older version of this file? These add the new columns safely.
alter table public.orders add column if not exists pickup_date date;
alter table public.orders add column if not exists pickup_time text;
alter table public.orders add column if not exists arrived_at timestamptz;
alter table public.orders add column if not exists subtotal int;
alter table public.orders add column if not exists discount int not null default 0;
alter table public.orders add column if not exists promo_code text;
alter table public.orders add column if not exists deal_labels jsonb not null default '[]'::jsonb;

-- Promo codes. Private: customers can only check one code at a time through check_promo().
create table if not exists public.promo_codes (
  code text primary key check (code ~ '^[A-Z0-9-]{3,20}$'),
  kind text not null check (kind in ('percent', 'peso')),
  value int not null check (value > 0),
  min_total int not null default 0,
  max_uses int,
  ends_on date,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function public.norm_text(t text) returns text
language sql immutable as $$ select lower(regexp_replace(trim(coalesce(t,'')), '\s+', ' ', 'g')) $$;

create index if not exists orders_person_idx on public.orders (public.norm_text(nickname), public.norm_text(grade_section));
create index if not exists orders_status_idx on public.orders (status);

create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
drop trigger if exists orders_touch on public.orders;
create trigger orders_touch before update on public.orders
  for each row execute function public.touch_updated_at();

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins
                 where lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;

-- ---------------------------------------------------------------------
-- Security: customers can't read the orders table at all.
-- They only go through the functions below.
-- ---------------------------------------------------------------------
alter table public.orders enable row level security;
alter table public.shop_settings enable row level security;
alter table public.admins enable row level security;
alter table public.promo_codes enable row level security;

-- Table permissions. Newer Supabase projects don't grant these automatically.
-- The row level security policies below still decide who can see which rows:
-- customers can't read orders at all, and only emails in public.admins can.
grant usage on schema public to anon, authenticated;
grant select, update, delete on public.orders to authenticated;
grant select on public.shop_settings to anon, authenticated;
grant update on public.shop_settings to authenticated;
grant select, insert, update, delete on public.promo_codes to authenticated;

drop policy if exists "admins manage promo codes" on public.promo_codes;
create policy "admins manage promo codes" on public.promo_codes
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admins manage orders" on public.orders;
create policy "admins manage orders" on public.orders
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "anyone reads settings" on public.shop_settings;
create policy "anyone reads settings" on public.shop_settings
  for select to anon, authenticated using (true);

drop policy if exists "admins edit settings" on public.shop_settings;
create policy "admins edit settings" on public.shop_settings
  for update to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------
-- Place an order (with fake-order protection)
-- ---------------------------------------------------------------------
drop function if exists public.place_order(text,text,text,text,text,jsonb,text,text);
drop function if exists public.place_order(text,text,text,text,text,jsonb,text,text,date);
drop function if exists public.place_order(text,text,text,text,text,jsonb,text,text,date,text);
create or replace function public.place_order(
  p_nickname text, p_grade_section text, p_pickup text, p_payment text,
  p_gcash_ref text, p_layout jsonb, p_folder text, p_src text, p_pickup_date date, p_pickup_time text,
  p_promo_code text default null
) returns text
language plpgsql security definer set search_path = public as $$
declare
  s public.shop_settings;
  v_nick text := public.norm_text(p_nickname);
  v_sec  text := public.norm_text(p_grade_section);
  v_item jsonb; v_prod jsonb; v_size jsonb; v_addon jsonb; v_addon_id text;
  v_units int; v_unit int; v_total int := 0; v_count int := 0;
  v_lines jsonb := '[]'::jsonb; v_subtotal int; v_discount int := 0; v_labels jsonb := '[]'::jsonb;
  v_p text; v_n int; v_k int; v_save int; v_best int; v_best_label text; v_deal jsonb;
  v_promo public.promo_codes; v_pcode text := nullif(upper(trim(coalesce(p_promo_code, ''))), '');
  v_code text;
begin
  select * into s from public.shop_settings where id = 1;

  if length(v_nick) < 2 or length(v_nick) > 24
     or length(v_sec) < 2 or length(v_sec) > 30
     or length(trim(coalesce(p_pickup,''))) < 3 or length(p_pickup) > 120
     or p_payment not in ('cash','gcash')
     or p_folder !~ '^[0-9]+-[a-z0-9]+$'
     or length(p_layout::text) > 80000
     or p_pickup_date is null or p_pickup_date < current_date or p_pickup_date > current_date + 45
     or length(trim(coalesce(p_pickup_time,''))) < 3 or length(p_pickup_time) > 40
     or jsonb_typeof(p_layout->'items') is distinct from 'array'
     or jsonb_array_length(p_layout->'items') < 1 or jsonb_array_length(p_layout->'items') > 10 then
    raise exception 'BAD_INPUT';
  end if;

  -- Work out the price on the server, from the prices set in admin
  for v_item in select value from jsonb_array_elements(p_layout->'items') loop
    v_prod := s.products -> (v_item->>'type');
    if v_prod is null or coalesce((v_prod->>'enabled')::boolean, false) = false then raise exception 'NOT_AVAILABLE'; end if;

    v_size := null;
    select e.value into v_size from jsonb_array_elements(coalesce(v_prod->'sizes', '[]'::jsonb)) e
      where e.value->>'id' = v_item->>'size' and coalesce((e.value->>'enabled')::boolean, true) limit 1;
    if v_size is null then raise exception 'NOT_AVAILABLE'; end if;

    if v_item->>'type' = 'stickers' then
      v_units := jsonb_array_length(coalesce(v_item->'sheets', '[]'::jsonb));
      if v_units < 1 then raise exception 'BAD_INPUT'; end if;
      if v_units > s.max_sheets then raise exception 'TOO_MANY_SHEETS'; end if;
      if exists (select 1 from jsonb_array_elements(v_item->'sheets') sh where jsonb_array_length(coalesce(sh.value->'items', '[]'::jsonb)) < 1) then
        raise exception 'BAD_INPUT';
      end if;
    else
      v_units := coalesce((v_item->>'qty')::int, 0);
      if v_units < 1 or v_units > 60 or v_item->'front'->>'path' is null then raise exception 'BAD_INPUT'; end if;
    end if;

    v_unit := coalesce((v_size->>'price')::int, 0);
    for v_addon_id in select jsonb_array_elements_text(coalesce(v_item->'addons', '[]'::jsonb)) loop
      v_addon := null;
      select e.value into v_addon from jsonb_array_elements(coalesce(v_prod->'addons', '[]'::jsonb)) e
        where e.value->>'id' = v_addon_id and coalesce((e.value->>'enabled')::boolean, true) limit 1;
      if v_addon is null then raise exception 'NOT_AVAILABLE'; end if;
      v_unit := v_unit + coalesce((v_addon->>'price')::int, 0);
    end loop;

    v_total := v_total + v_units * v_unit;
    v_count := v_count + v_units;
    v_lines := v_lines || jsonb_build_object('type', v_item->>'type', 'price', v_unit, 'units', v_units);
  end loop;
  v_subtotal := v_total;

  -- Deals. Per product, the better of "buy X get Y free" and "bulk discount" applies.
  for v_p in select distinct l->>'type' from jsonb_array_elements(v_lines) l loop
    select sum((l->>'units')::int) into v_n from jsonb_array_elements(v_lines) l where l->>'type' = v_p;
    v_best := 0; v_best_label := null;
    for v_deal in select value from jsonb_array_elements(coalesce(s.deals, '[]'::jsonb))
                  where coalesce((value->>'enabled')::boolean, false) and value->>'product' = v_p and value->>'type' in ('freebie', 'bulk', 'tiers') loop
      if v_deal->>'type' = 'freebie' then
        v_k := (v_n / greatest(1, (v_deal->>'buy')::int + (v_deal->>'free')::int)) * (v_deal->>'free')::int;
        select coalesce(sum(price), 0) into v_save from (
          select (l->>'price')::int as price from jsonb_array_elements(v_lines) l
          cross join generate_series(1, (l->>'units')::int)
          where l->>'type' = v_p order by 1 limit v_k) z;
      elsif v_deal->>'type' = 'tiers' then
        -- Class pack: the more you order, the more comes off each one
        select coalesce(max((tr->>'off')::int), 0) * v_n into v_save
          from jsonb_array_elements(coalesce(v_deal->'tiers', '[]'::jsonb)) tr where (tr->>'min')::int <= v_n;
      else
        v_save := case when v_n >= (v_deal->>'min')::int then v_n * (v_deal->>'off')::int else 0 end;
      end if;
      if v_save > v_best then v_best := v_save; v_best_label := v_deal->>'label'; end if;
    end loop;
    if v_best > 0 then v_discount := v_discount + v_best; v_labels := v_labels || to_jsonb(v_best_label); end if;
  end loop;
  -- Combos: everything listed is in the order
  for v_deal in select value from jsonb_array_elements(coalesce(s.deals, '[]'::jsonb))
                where coalesce((value->>'enabled')::boolean, false) and value->>'type' = 'combo' loop
    if not exists (select 1 from jsonb_array_elements_text(v_deal->'products') pr
                   where not exists (select 1 from jsonb_array_elements(v_lines) l where l->>'type' = pr.value)) then
      v_discount := v_discount + (v_deal->>'off')::int; v_labels := v_labels || to_jsonb(v_deal->>'label');
    end if;
  end loop;
  v_discount := least(v_discount, v_subtotal);

  -- Promo code
  if v_pcode is not null then
    select * into v_promo from public.promo_codes
      where code = v_pcode and active and (ends_on is null or ends_on >= current_date);
    if not found then raise exception 'BAD_CODE'; end if;
    if v_subtotal - v_discount < v_promo.min_total then raise exception 'CODE_MIN'; end if;
    if v_promo.max_uses is not null and (select count(*) from public.orders
        where promo_code = v_pcode and status not in ('cancelled', 'rejected')) >= v_promo.max_uses then
      raise exception 'CODE_USED_UP';
    end if;
    v_discount := least(v_subtotal, v_discount + case when v_promo.kind = 'percent'
      then floor((v_subtotal - v_discount) * v_promo.value / 100.0)::int else v_promo.value end);
    v_labels := v_labels || to_jsonb('Code ' || v_pcode);
  end if;
  v_total := v_subtotal - v_discount;

  -- One unfinished order per person
  if exists (select 1 from public.orders
             where public.norm_text(nickname) = v_nick and public.norm_text(grade_section) = v_sec
               and status in ('pending','approved','printing','ready')) then
    raise exception 'ACTIVE_ORDER';
  end if;

  -- Too many missed pickups
  if (select count(*) from public.orders
      where public.norm_text(nickname) = v_nick and public.norm_text(grade_section) = v_sec
        and status = 'noshow') >= s.max_noshows then
    raise exception 'BLOCKED';
  end if;

  -- Flood protection: more than 30 orders in 10 minutes is not normal
  if (select count(*) from public.orders where created_at > now() - interval '10 minutes') > 30 then
    raise exception 'BUSY';
  end if;

  loop
    v_code := 'STK-' || (select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), '')
                         from generate_series(1, 4));
    exit when not exists (select 1 from public.orders where code = v_code);
  end loop;

  -- sheet_count holds the number of things in the order (sheets + pins + posters + keychains)
  insert into public.orders (code, nickname, grade_section, pickup, pickup_date, pickup_time, payment, gcash_ref,
                             layout, folder, sheet_count, total, src, subtotal, discount, promo_code, deal_labels)
  values (v_code, trim(p_nickname), trim(p_grade_section), trim(p_pickup), p_pickup_date, trim(p_pickup_time), p_payment,
          nullif(trim(left(coalesce(p_gcash_ref, ''), 40)), ''),
          p_layout, p_folder, v_count, v_total,
          nullif(left(coalesce(p_src, ''), 40), ''), v_subtotal, v_discount, v_pcode, v_labels);
  return v_code;
end $$;

-- Customer looks up their own order (needs code AND nickname)
create or replace function public.get_order(p_code text, p_nickname text) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('code', code, 'nickname', nickname, 'status', status, 'pickup', pickup,
    'pickup_date', pickup_date, 'pickup_time', pickup_time, 'arrived', arrived_at is not null,
    'payment', payment, 'total', total, 'sheet_count', sheet_count, 'reject_reason', reject_reason,
    'confirmed', confirmed, 'paid', paid, 'created_at', created_at)
  from public.orders
  where code = upper(trim(p_code)) and public.norm_text(nickname) = public.norm_text(p_nickname)
  limit 1;
$$;

-- Customer taps "I'll be there!"
create or replace function public.confirm_order(p_code text, p_nickname text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.orders set confirmed = true
  where code = upper(trim(p_code)) and public.norm_text(nickname) = public.norm_text(p_nickname)
    and status in ('approved','printing','ready');
  return found;
end $$;

-- Customer cancels before printing
create or replace function public.cancel_order(p_code text, p_nickname text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.orders set status = 'cancelled'
  where code = upper(trim(p_code)) and public.norm_text(nickname) = public.norm_text(p_nickname)
    and status in ('pending','approved');
  return found;
end $$;

-- Customer taps "I'm here" at the pickup spot (only works once the order is ready)
create or replace function public.mark_arrived(p_code text, p_nickname text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.orders set arrived_at = now()
  where code = upper(trim(p_code)) and public.norm_text(nickname) = public.norm_text(p_nickname)
    and status = 'ready';
  return found;
end $$;

-- Customer checks a promo code before ordering
create or replace function public.check_promo(p_code text) returns json
language plpgsql stable security definer set search_path = public as $$
declare v public.promo_codes; v_used int;
begin
  select * into v from public.promo_codes
    where code = upper(trim(coalesce(p_code, ''))) and active and (ends_on is null or ends_on >= current_date);
  if not found then return null; end if;
  select count(*) into v_used from public.orders where promo_code = v.code and status not in ('cancelled', 'rejected');
  return json_build_object('code', v.code, 'kind', v.kind, 'value', v.value, 'min_total', v.min_total,
    'used_up', v.max_uses is not null and v_used >= v.max_uses);
end $$;

grant execute on function public.place_order(text,text,text,text,text,jsonb,text,text,date,text,text) to anon, authenticated;
grant execute on function public.check_promo(text) to anon, authenticated;
grant execute on function public.mark_arrived(text,text) to anon, authenticated;
grant execute on function public.get_order(text,text) to anon, authenticated;
grant execute on function public.confirm_order(text,text) to anon, authenticated;
grant execute on function public.cancel_order(text,text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Picture storage: private bucket, 5 MB per picture.
-- Customers can upload; only admins can view or delete.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('sticker-uploads', 'sticker-uploads', false, 5242880, array['image/png','image/jpeg'])
on conflict (id) do nothing;

drop policy if exists "sticker uploads: anyone can upload" on storage.objects;
create policy "sticker uploads: anyone can upload" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'sticker-uploads' and (storage.foldername(name))[1] = 'orders');

drop policy if exists "sticker uploads: admins read" on storage.objects;
create policy "sticker uploads: admins read" on storage.objects
  for select to authenticated
  using (bucket_id = 'sticker-uploads' and public.is_admin());

drop policy if exists "sticker uploads: admins delete" on storage.objects;
create policy "sticker uploads: admins delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'sticker-uploads' and public.is_admin());

-- =====================================================================
-- STEP AT THE END: put the admin's login email here and run this line.
-- (Create the same user in Authentication → Users first.)
-- =====================================================================
-- insert into public.admins (email) values ('friend@example.com');
