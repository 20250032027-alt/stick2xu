-- =====================================================================
-- Stick2XU: run this whole file in Supabase → SQL Editor.
-- It's safe to run again after updates; it only adds what's missing.
-- Then add the admin's email at the bottom (see STEP AT THE END).
-- =====================================================================

create extension if not exists pgcrypto;

-- Shop settings (one row). Change prices here, no code edits needed.
create table if not exists public.shop_settings (
  id int primary key default 1 check (id = 1),
  price_per_sheet int not null default 50,
  max_sheets int not null default 3,
  max_noshows int not null default 2
);
alter table public.shop_settings add column if not exists signal_verb text not null default 'holding';
alter table public.shop_settings add column if not exists signal_item text not null default 'a Stick2XU sign';
insert into public.shop_settings (id) values (1) on conflict do nothing;
-- Already ran this file before? Run this line to switch to ₱50:
-- update public.shop_settings set price_per_sheet = 50 where id = 1;

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
create or replace function public.place_order(
  p_nickname text, p_grade_section text, p_pickup text, p_payment text,
  p_gcash_ref text, p_layout jsonb, p_folder text, p_src text, p_pickup_date date, p_pickup_time text
) returns text
language plpgsql security definer set search_path = public as $$
declare
  s public.shop_settings;
  v_nick text := public.norm_text(p_nickname);
  v_sec  text := public.norm_text(p_grade_section);
  v_sheets int;
  v_items int;
  v_code text;
begin
  select * into s from public.shop_settings where id = 1;

  if length(v_nick) < 2 or length(v_nick) > 24
     or length(v_sec) < 2 or length(v_sec) > 30
     or length(trim(coalesce(p_pickup,''))) < 3 or length(p_pickup) > 120
     or p_payment not in ('cash','gcash')
     or p_folder !~ '^[0-9]+-[a-z0-9]+$'
     or length(p_layout::text) > 30000
     or p_pickup_date is null or p_pickup_date < current_date or p_pickup_date > current_date + 45
     or length(trim(coalesce(p_pickup_time,''))) < 3 or length(p_pickup_time) > 40 then
    raise exception 'BAD_INPUT';
  end if;

  v_sheets := jsonb_array_length(coalesce(p_layout->'sheets', '[]'::jsonb));
  if v_sheets < 1 then raise exception 'BAD_INPUT'; end if;
  if v_sheets > s.max_sheets then raise exception 'TOO_MANY_SHEETS'; end if;

  select count(*) into v_items
  from jsonb_array_elements(p_layout->'sheets') sh, jsonb_array_elements(sh->'items') it;
  if v_items < 1 then raise exception 'BAD_INPUT'; end if;

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

  insert into public.orders (code, nickname, grade_section, pickup, pickup_date, pickup_time, payment, gcash_ref,
                             layout, folder, sheet_count, total, src)
  values (v_code, trim(p_nickname), trim(p_grade_section), trim(p_pickup), p_pickup_date, trim(p_pickup_time), p_payment,
          nullif(trim(left(coalesce(p_gcash_ref, ''), 40)), ''),
          p_layout, p_folder, v_sheets, v_sheets * s.price_per_sheet,
          nullif(left(coalesce(p_src, ''), 40), ''));
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

grant execute on function public.place_order(text,text,text,text,text,jsonb,text,text,date,text) to anon, authenticated;
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
