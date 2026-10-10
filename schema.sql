-- =====================================================================
-- Stick2It: run this whole file in Supabase → SQL Editor.
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
alter table public.shop_settings add column if not exists signal_item text not null default 'a Stick2It sign';
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
-- Shop details edited in admin → Settings (pickup schedule, gates, GCash, limits, sizes)
alter table public.shop_settings add column if not exists config jsonb not null default '{}'::jsonb;
insert into public.shop_settings (id) values (1) on conflict do nothing;
-- New name: the pickup signal follows it, unless you changed it yourself
update public.shop_settings set signal_item = 'a Stick2It sign' where id = 1 and signal_item = 'a Stick2XU sign';
-- New prices: stickers ₱45 a sheet, A4 posters ₱50 (only changes them if still at the old starting price)
update public.shop_settings set products = jsonb_set(products, '{stickers,sizes,0,price}', '45')
  where id = 1 and products->'stickers'->'sizes'->0->>'price' = '50';
update public.shop_settings set products = jsonb_set(products, '{posters,sizes,0,price}', '50')
  where id = 1 and products->'posters'->'sizes'->0->>'price' = '40';
-- Prints (plain paper), added once
update public.shop_settings set products = products || '{"prints": {"enabled": true,
  "sizes": [{"id": "a4", "price": 5, "enabled": true}, {"id": "short", "price": 5, "enabled": false}, {"id": "long", "price": 6, "enabled": false}],
  "addons": [{"id": "color", "label": "Color", "note": "instead of black and white", "price": 5, "enabled": true}]}}'::jsonb
  where id = 1 and not (products ? 'prints');
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
alter table public.orders add column if not exists missed int not null default 0;          -- missed pickups on this order (1 = held for the next day)
alter table public.orders add column if not exists reschedules int not null default 0;     -- times the customer moved their pickup
alter table public.orders add column if not exists refunded boolean not null default false;
alter table public.orders add column if not exists rush_fee int not null default 0;

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

-- Order lookups: the full name, or just the first name, both work (any capitals or spacing)
create or replace function public.name_match(stored text, given text) returns boolean
language sql immutable as $$
  select public.norm_text(stored) = public.norm_text(given)
      or (position(' ' in public.norm_text(given)) = 0 and length(public.norm_text(given)) >= 2
          and split_part(public.norm_text(stored), ' ', 1) = public.norm_text(given))
$$;

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
-- =====================================================================
-- Pickup capacity: one gate per time slot for each person on pickup duty, and limits per slot and per day.
-- Settings (admin → Shop details → Pickup rules): sellers_at_pickup, max_per_slot, max_per_day (0 = no limit).
-- =====================================================================
create or replace function public.check_pickup(p_date date, p_time text, p_pickup text, p_skip_code text default null) returns void
language plpgsql security definer set search_path = public as $$
declare s public.shop_settings; v_sellers int; v_slot int; v_day int; v_gates int;
begin
  -- one booking at a time per day, so two people ordering at the same moment can't both take the last spot
  perform pg_advisory_xact_lock(hashtext('stick2xu-pickup-' || p_date::text));
  select * into s from public.shop_settings where id = 1;
  v_sellers := coalesce((s.config->>'sellers_at_pickup')::int, 1);
  v_slot := coalesce((s.config->>'max_per_slot')::int, 8);
  v_day := coalesce((s.config->>'max_per_day')::int, 15);
  if v_day > 0 and (select count(*) from public.orders where pickup_date = p_date and status in ('pending','approved','printing','ready')
                    and code is distinct from p_skip_code) >= v_day then raise exception 'DAY_FULL'; end if;
  if v_slot > 0 and (select count(*) from public.orders where pickup_date = p_date and pickup_time = trim(p_time)
                     and status in ('pending','approved','printing','ready') and code is distinct from p_skip_code) >= v_slot then raise exception 'SLOT_FULL'; end if;
  if v_sellers > 0 and not exists (select 1 from public.orders where pickup_date = p_date and pickup_time = trim(p_time) and pickup = trim(p_pickup)
                                   and status in ('pending','approved','printing','ready') and code is distinct from p_skip_code) then
    select count(distinct pickup) into v_gates from public.orders where pickup_date = p_date and pickup_time = trim(p_time)
      and status in ('pending','approved','printing','ready') and code is distinct from p_skip_code;
    if v_gates >= v_sellers then raise exception 'GATE_TAKEN'; end if;
  end if;
end $$;
revoke all on function public.check_pickup(date, text, text, text) from public, anon, authenticated;

-- What's already booked (counts only, no names), so checkout can grey out full slots and taken gates
create or replace function public.pickup_availability(p_from date, p_to date)
returns table (pickup_date date, pickup_time text, pickup text, n int)
language sql stable security definer set search_path = public as $$
  select o.pickup_date, o.pickup_time, o.pickup, count(*)::int from public.orders o
  where o.pickup_date between p_from and least(p_to, p_from + 60) and o.status in ('pending','approved','printing','ready')
  group by 1, 2, 3
$$;
grant execute on function public.pickup_availability(date, date) to anon, authenticated;

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
  v_units int; v_unit int; v_total int := 0; v_count int := 0; v_maxq int;
  v_tiles int; v_pages int; v_has_prints boolean := false; v_only_prints boolean := true;
  v_today date := (now() at time zone 'Asia/Manila')::date; v_next date; v_rush int := 0; v_tm text[]; v_mins int;
  v_lines jsonb := '[]'::jsonb; v_subtotal int; v_discount int := 0; v_labels jsonb := '[]'::jsonb;
  v_p text; v_n int; v_k int; v_save int; v_best int; v_best_label text; v_deal jsonb;
  v_promo public.promo_codes; v_pcode text := nullif(upper(trim(coalesce(p_promo_code, ''))), '');
  v_code text;
begin
  select * into s from public.shop_settings where id = 1;

  if length(v_nick) < 2 or length(v_nick) > 60
     or length(v_sec) < 2 or length(v_sec) > 30
     or length(trim(coalesce(p_pickup,''))) < 3 or length(p_pickup) > 120
     or p_payment not in ('cash','gcash')
     or p_folder !~ '^[0-9]+-[a-z0-9]+$'
     or length(p_layout::text) > 80000
     or p_pickup_date is null or p_pickup_date < v_today or p_pickup_date > v_today + 45
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
      -- per-product limit from admin settings (pins default 60, others 20), never above 200
      v_maxq := least(200, coalesce((s.config->'max_qty'->>(v_item->>'type'))::int, case when v_item->>'type' = 'pins' then 60 else 20 end));
      if v_units < 1 or v_units > v_maxq then raise exception 'BAD_INPUT'; end if;
      if v_item->>'type' = 'prints' then
        v_pages := coalesce((v_item->>'pages')::int, 0);
        if v_pages < 1 or v_pages > 500 or jsonb_array_length(coalesce(v_item->'files', '[]'::jsonb)) < 1 then raise exception 'BAD_INPUT'; end if;
        v_units := v_units * v_pages;      -- copies x pages
        v_has_prints := true;
      elsif v_item->>'type' = 'posters' and v_item->>'mode' = 'pages' then
        -- a ready-made PDF (like Rasterbator's): printed page by page as it is
        if v_item->'pdf'->>'path' is null then raise exception 'BAD_INPUT'; end if;
      elsif v_item->'front'->>'path' is null then raise exception 'BAD_INPUT';
      end if;
    end if;

    if v_item->>'type' <> 'prints' then v_only_prints := false; end if;
    v_unit := coalesce((v_size->>'price')::int, 0);
    -- big posters: first sheet at the size price, each extra sheet costs extra
    if v_item->>'type' = 'posters' then
      -- sheets across x sheets down (each 1 to 6), or an older fixed sheet count
      if v_item->>'mode' = 'pages' then
        v_tiles := coalesce((v_item->>'pages')::int, 0);      -- one sheet per page of their PDF
        if v_tiles < 1 or v_tiles > 24 then raise exception 'BAD_INPUT'; end if;
      else
        v_tiles := coalesce((v_item->>'cols')::int * (v_item->>'rows')::int, (v_item->>'tiles')::int, 1);
        if v_tiles < 1 or v_tiles > 24 or coalesce((v_item->>'cols')::int, 1) not between 1 and 6
           or coalesce((v_item->>'rows')::int, 1) not between 1 and 6 then raise exception 'BAD_INPUT'; end if;
      end if;
      v_unit := v_unit + (v_tiles - 1) * coalesce((s.config->>'poster_extra_sheet')::int, 30);
    end if;
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

  -- Pickup today is only for prints-only orders, with enough prep time before the pickup time
  if p_pickup_date = v_today then
    if not (v_has_prints and v_only_prints) then raise exception 'TOO_SOON'; end if;
    v_tm := regexp_match(p_pickup_time, '(\d{1,2}):(\d{2})\s*(AM|PM)', 'i');
    if v_tm is not null then
      v_mins := (v_tm[1]::int % 12 + case when upper(v_tm[3]) = 'PM' then 12 else 0 end) * 60 + v_tm[2]::int;
      if v_mins - extract(hour from now() at time zone 'Asia/Manila')::int * 60 - extract(minute from now() at time zone 'Asia/Manila')::int
         < coalesce((s.config->>'prep_hours')::numeric, 2) * 60 then raise exception 'TOO_SOON'; end if;
    end if;
  end if;
  -- Rush fee for prints: same day, or the next school day
  if v_has_prints then
    v_next := v_today + 1;
    while extract(dow from v_next) in (0, 6) loop v_next := v_next + 1; end loop;
    if p_pickup_date = v_today then v_rush := coalesce((s.config->>'rush_same_day')::int, 20);
    elsif p_pickup_date = v_next then v_rush := coalesce((s.config->>'rush_next_day')::int, 10);
    end if;
    if v_rush > 0 then v_total := v_total + v_rush; v_labels := v_labels || to_jsonb('Rush fee ₱' || v_rush); end if;
  end if;

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

  perform public.check_pickup(p_pickup_date, p_pickup_time, p_pickup, null);

  -- sheet_count holds the number of things in the order (sheets + pins + posters + keychains)
  insert into public.orders (code, nickname, grade_section, pickup, pickup_date, pickup_time, payment, gcash_ref,
                             layout, folder, sheet_count, total, src, subtotal, discount, promo_code, deal_labels, rush_fee, confirmed)
  values (v_code, trim(p_nickname), trim(p_grade_section), trim(p_pickup), p_pickup_date, trim(p_pickup_time), p_payment,
          nullif(trim(left(coalesce(p_gcash_ref, ''), 40)), ''),
          p_layout, p_folder, v_count, v_total,
          nullif(left(coalesce(p_src, ''), 40), ''), v_subtotal, v_discount, v_pcode, v_labels, v_rush,
          -- pickups inside the confirm window (like rush prints) count as confirmed right away
          p_pickup_date - coalesce((s.config->>'confirm_days_before')::int, 1) <= v_today);
  return v_code;
end $$;

-- Customer looks up their own order (needs code AND nickname)
create or replace function public.get_order(p_code text, p_nickname text) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('code', code, 'nickname', nickname, 'status', status, 'pickup', pickup,
    'pickup_date', pickup_date, 'pickup_time', pickup_time, 'arrived', arrived_at is not null,
    'payment', payment, 'total', total, 'sheet_count', sheet_count, 'reject_reason', reject_reason,
    'confirmed', confirmed, 'paid', paid, 'missed', missed, 'reschedules', reschedules, 'created_at', created_at)
  from public.orders
  where code = upper(trim(p_code)) and public.name_match(nickname, p_nickname)
  limit 1;
$$;

-- Customer taps "I'll be there". Orders are only printed once confirmed.
create or replace function public.confirm_order(p_code text, p_nickname text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.orders set confirmed = true
  where code = upper(trim(p_code)) and public.name_match(nickname, p_nickname)
    and status in ('pending','approved','printing','ready');
  return found;
end $$;

-- Customer moves their own pickup to another open pickup day (limited number of times)
create or replace function public.reschedule_order(p_code text, p_nickname text, p_date date, p_time text) returns boolean
language plpgsql security definer set search_path = public as $$
declare s public.shop_settings; v_days jsonb; v_max int; v_pick text;
begin
  select * into s from public.shop_settings where id = 1;
  v_days := coalesce(s.config->'pickup_weekdays', '[2,5]'::jsonb) || coalesce(s.config->'print_weekdays', '[1,2,3,4,5]'::jsonb);
  v_max := coalesce((s.config->>'max_reschedules')::int, 2);
  if p_date is null or p_date < current_date or p_date > current_date + 45
     or not (v_days @> to_jsonb(extract(dow from p_date)::int))
     or coalesce(s.config->'no_pickup_dates', '[]'::jsonb) @> to_jsonb(p_date::text)
     or length(trim(coalesce(p_time, ''))) < 3 or length(p_time) > 40 then
    raise exception 'BAD_DATE';
  end if;
  select pickup into v_pick from public.orders where code = upper(trim(p_code)) and public.name_match(nickname, p_nickname);
  if v_pick is not null then perform public.check_pickup(p_date, p_time, v_pick, upper(trim(p_code))); end if;
  update public.orders
     set pickup_date = p_date, pickup_time = trim(p_time), reschedules = reschedules + 1, arrived_at = null, confirmed = true
   where code = upper(trim(p_code)) and public.name_match(nickname, p_nickname)
     and status in ('pending','approved','printing','ready') and reschedules < v_max;
  if not found then raise exception 'NO_RESCHEDULE'; end if;
  return true;
end $$;

-- Customer cancels before printing
create or replace function public.cancel_order(p_code text, p_nickname text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.orders set status = 'cancelled'
  where code = upper(trim(p_code)) and public.name_match(nickname, p_nickname)
    and status in ('pending','approved');
  return found;
end $$;

-- Customer taps "I'm here" at the pickup spot (only works once the order is ready)
create or replace function public.mark_arrived(p_code text, p_nickname text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.orders set arrived_at = now()
  where code = upper(trim(p_code)) and public.name_match(nickname, p_nickname)
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
grant execute on function public.reschedule_order(text,text,date,text) to anon, authenticated;
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
update storage.buckets set file_size_limit = 20971520, allowed_mime_types = array['image/png','image/jpeg','application/pdf'] where id = 'sticker-uploads';

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

-- =====================================================================
-- Telegram alerts: the database messages your Telegram the moment something happens
-- (new order, customer at the gate, confirmed, moved, cancelled). Set it up in
-- admin → Settings → Telegram alerts. Needs the pg_net extension (turned on below).
-- =====================================================================
do $$ begin
  create extension if not exists pg_net with schema extensions;
exception when others then raise notice 'pg_net is not available here. Turn it on in Supabase: Database > Extensions > pg_net.';
end $$;

create table if not exists public.telegram (
  id int primary key default 1 check (id = 1),
  enabled boolean not null default false,
  bot_token text,
  chat_id text,
  notify jsonb not null default '{"new": true, "arrived": true, "confirmed": true, "moved": true, "cancelled": true}'::jsonb
);
insert into public.telegram (id) values (1) on conflict do nothing;
alter table public.telegram enable row level security;
grant select, insert, update on public.telegram to authenticated;
drop policy if exists "admins manage telegram" on public.telegram;
create policy "admins manage telegram" on public.telegram
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.tg_esc(t text) returns text language sql immutable as $$
  select replace(replace(replace(coalesce(t, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;')
$$;

-- Sends one message. Never lets a Telegram problem block an order.
create or replace function public.tg_send(p_text text, p_force boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare t public.telegram;
begin
  select * into t from public.telegram where id = 1;
  if t is null or (not t.enabled and not p_force) or coalesce(t.bot_token, '') = '' or coalesce(t.chat_id, '') = '' then return; end if;
  perform net.http_post(
    url := 'https://api.telegram.org/bot' || t.bot_token || '/sendMessage',
    body := jsonb_build_object('chat_id', t.chat_id, 'text', p_text, 'parse_mode', 'HTML', 'disable_web_page_preview', true),
    headers := '{"Content-Type": "application/json"}'::jsonb);
exception when others then
  raise notice 'Telegram send skipped: %', sqlerrm;
end $$;
revoke all on function public.tg_send(text, boolean) from public, anon, authenticated;

-- Admin's "Send test message" button
create or replace function public.telegram_test() returns text
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if not exists (select 1 from pg_extension where extname = 'pg_net') then raise exception 'NO_PGNET'; end if;
  perform public.tg_send('<b>Stick2It is connected.</b>' || E'\n' || 'Order alerts will be sent to this chat.', true);
  return 'sent';
end $$;
grant execute on function public.telegram_test() to authenticated;

create or replace function public.orders_notify() returns trigger
language plpgsql security definer set search_path = public as $$
declare t public.telegram; n jsonb; items text; v_when text; who text; v_by date; v_days int;
begin
  select * into t from public.telegram where id = 1;
  if t is null or not t.enabled then return new; end if;
  n := t.notify;
  who := public.tg_esc(new.nickname) || ', ' || public.tg_esc(new.grade_section);
  v_when := coalesce(to_char(new.pickup_date, 'Dy, Mon FMDD'), 'no date') || coalesce(', ' || new.pickup_time, '') || ', ' || public.tg_esc(new.pickup);

  -- Order placed
  if tg_op = 'INSERT' then
    if coalesce((n->>'new')::boolean, true) then
      select string_agg('- ' ||
          case when it->>'type' = 'stickers'
               then 'Stickers, ' || jsonb_array_length(coalesce(it->'sheets', '[]'::jsonb))
                    || case when jsonb_array_length(coalesce(it->'sheets', '[]'::jsonb)) = 1 then ' sheet' else ' sheets' end
               when it->>'type' = 'prints' then 'Prints ' || coalesce(it->>'size_label', '') || ', ' || coalesce(it->>'pages', '?') || ' page(s) x '
                    || coalesce(it->>'qty', '1') || ' cop' || case when coalesce(it->>'qty', '1') = '1' then 'y' else 'ies' end
                    || case when (it->>'duplex')::boolean then ', double-sided' else '' end
               else initcap(it->>'type') || coalesce(' ' || (it->>'size_label'), '') || ' x ' || coalesce(it->>'qty', '1')
                    || case when coalesce((it->>'tiles')::int, 1) > 1 then ' (' || (it->>'tiles') || ' sheets each)' else '' end end
          || case when jsonb_array_length(coalesce(it->'addon_labels', '[]'::jsonb)) > 0
                  then ' + ' || (select string_agg(x, ', ') from jsonb_array_elements_text(it->'addon_labels') x) else '' end,
          E'\n')
        into items from jsonb_array_elements(coalesce(new.layout->'items', '[]'::jsonb)) it;
      perform public.tg_send('<b>Order placed: ' || new.code || '</b>' || E'\n' || who
        || E'\n' || public.tg_esc(coalesce(items, ''))
        || E'\n' || 'Total: ₱' || new.total || case when coalesce(new.discount, 0) > 0 then ' (saved ₱' || new.discount || ')' else '' end
        || case when coalesce(new.rush_fee, 0) > 0 then ', includes rush fee ₱' || new.rush_fee else '' end
        || E'\n' || 'Payment: ' || case when new.payment = 'gcash' then 'GCash' || coalesce(', ref ' || public.tg_esc(new.gcash_ref), ', no ref yet') else 'Cash at pickup' end
        || E'\n' || 'Pickup: ' || v_when
        || E'\n' || 'Needs your approval in admin.');
    end if;
    return new;
  end if;

  -- Customer arrived at the pickup spot
  if new.arrived_at is not null and old.arrived_at is null and coalesce((n->>'arrived')::boolean, true) then
    perform public.tg_send('<b>Arrived: ' || new.code || '</b>' || E'\n' || who || ' is at ' || public.tg_esc(new.pickup) || ' now.'
      || E'\n' || case when new.paid then 'Already paid.' else 'Collect ₱' || new.total || '.' end);
  end if;

  -- Customer changed their pickup date (admin moves and missed-pickup holds don't message)
  if new.reschedules > old.reschedules then
    if coalesce((n->>'moved')::boolean, true) then
      perform public.tg_send('<b>Pickup changed: ' || new.code || '</b>' || E'\n' || who || ' moved their pickup to ' || v_when || '.');
    end if;
  -- Customer confirmed ("I'll be there"), only when nothing else about the pickup changed
  elsif new.confirmed and not old.confirmed and new.pickup_date is not distinct from old.pickup_date
        and new.status in ('pending', 'approved', 'printing') and coalesce((n->>'confirmed')::boolean, true) then
    perform public.tg_send('<b>Confirmed: ' || new.code || '</b>' || E'\n' || who || ' will pick up ' || v_when || '.'
      || E'\n' || case when new.status = 'pending' then 'Approve the design, then print.' else 'OK to print.' end);
  end if;

  -- Cancelled by the customer, or released because it wasn't confirmed in time
  if new.status = 'cancelled' and old.status <> 'cancelled' and coalesce((n->>'cancelled')::boolean, true) then
    if new.reject_reason = 'Not confirmed in time' then
      select coalesce((config->>'confirm_days_before')::int, 1) into v_days from public.shop_settings where id = 1;
      v_by := new.pickup_date - coalesce(v_days, 1);
      perform public.tg_send('<b>Released: ' || new.code || '</b>' || E'\n' || who || ' did not confirm by '
        || coalesce(to_char(v_by, 'Dy, Mon FMDD'), 'the deadline') || '. Nothing to print.');
    else
      perform public.tg_send('<b>Cancelled: ' || new.code || '</b>' || E'\n' || who || ' cancelled their order.'
        || case when new.paid and new.payment = 'gcash' then E'\n' || 'They paid by GCash. Send back ₱' || new.total || '.' else '' end);
    end if;
  end if;
  return new;
end $$;

drop trigger if exists orders_notify on public.orders;
create trigger orders_notify after insert or update on public.orders
  for each row execute function public.orders_notify();

-- =====================================================================
-- Business: supplies (inventory), what each product uses, equipment, partners.
-- Private: only admins can read or change it.
-- =====================================================================
create table if not exists public.business (
  id int primary key default 1 check (id = 1),
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
insert into public.business (id) values (1) on conflict do nothing;
alter table public.business enable row level security;
grant select, insert, update on public.business to authenticated;
drop policy if exists "admins manage business" on public.business;
create policy "admins manage business" on public.business
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- marks orders whose supplies were already taken out of stock (so it only happens once)
alter table public.orders add column if not exists stock_used boolean not null default false;

-- low-stock alert to Telegram (admin only; respects the Telegram on/off switch)
create or replace function public.business_alert(p_text text) returns void
language plpgsql security definer set search_path = public as $$
declare t public.telegram;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  select * into t from public.telegram where id = 1;
  if t is null or not coalesce((t.notify->>'stock')::boolean, true) then return; end if;
  perform public.tg_send(left(p_text, 3500));
end $$;
grant execute on function public.business_alert(text) to authenticated;

-- When an order was picked up. Set once, so later edits (like picture cleanup) never move it.
alter table public.orders add column if not exists done_at timestamptz;
update public.orders set done_at = updated_at where status = 'done' and done_at is null;
create or replace function public.orders_done_at() returns trigger
language plpgsql as $$
begin
  if new.status = 'done' and (tg_op = 'INSERT' or old.status is distinct from 'done') then new.done_at = now(); end if;
  if new.status <> 'done' then new.done_at = null; end if;
  return new;
end $$;
drop trigger if exists orders_done_at on public.orders;
create trigger orders_done_at before insert or update on public.orders
  for each row execute function public.orders_done_at();
