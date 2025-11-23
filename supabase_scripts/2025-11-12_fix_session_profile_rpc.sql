-- 2025-11-12_fix_session_profile_rpc.sql
-- Purpose: Provide missing RPCs used by the app during session bootstrap
-- - ensure_user_profile_public: idempotently creates/updates public.users and optionally client profile
-- - create_user_profile_public: legacy wrapper that calls ensure_user_profile_public
-- - ensure_client_profile_and_account: idempotently ensures client_profiles and accounts for a user
--
-- Notes:
-- - This script is aligned with the current schema where address/coords live in client_profiles, not in users
-- - Functions run as SECURITY DEFINER and set search_path to public for safety

set check_function_bodies = off;

-- Helper: normalize role to canonical values expected by the app
create or replace function public._normalize_role(p_role text)
returns text
language plpgsql as $$
declare
  v text := lower(coalesce(p_role, 'client'));
begin
  if v in ('cliente','usuario','user') then
    return 'client';
  elsif v in ('restaurante') then
    return 'restaurant';
  elsif v in ('repartidor','rider','courier','delivery','delivery_agent') then
    return 'delivery_agent';
  elsif v in ('admin','administrator') then
    return 'admin';
  else
    return 'client';
  end if;
end $$;

-- Idempotent creator/updater for public.users and client_profiles
create or replace function public.ensure_user_profile_public(
  p_user_id uuid,
  p_email text,
  p_name text default '',
  p_role text default 'client',
  p_phone text default null,
  -- Legacy/optional inputs (ignored by users, persisted in client_profiles when present)
  p_address text default null,
  p_lat double precision default null,
  p_lon double precision default null,
  p_address_structured jsonb default null,
  p_is_temp_password boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_role text := public._normalize_role(p_role);
begin
  -- 1) Ensure the users row exists (do not store address here in new schema)
  insert into public.users as u (id, email, name, phone, role, created_at, updated_at, email_confirm)
  values (p_user_id, p_email, nullif(btrim(p_name),''), nullif(btrim(coalesce(p_phone,''))), v_role, v_now, v_now, false)
  on conflict (id) do update set
    email = excluded.email,
    name = coalesce(nullif(excluded.name,''), u.name),
    phone = coalesce(nullif(excluded.phone,''), u.phone),
    role = excluded.role,
    updated_at = v_now;

  -- 2) If role is client, ensure client_profiles row and persist optional address/coords
  if v_role = 'client' then
    insert into public.client_profiles as cp (user_id, address, lat, lon, address_structured, created_at, updated_at)
    values (p_user_id,
            nullif(btrim(coalesce(p_address,''))),
            p_lat,
            p_lon,
            p_address_structured,
            v_now,
            v_now)
    on conflict (user_id) do update set
      address = coalesce(nullif(excluded.address,''), cp.address),
      lat = coalesce(excluded.lat, cp.lat),
      lon = coalesce(excluded.lon, cp.lon),
      address_structured = coalesce(excluded.address_structured, cp.address_structured),
      updated_at = v_now;

    -- Also ensure a client account exists with zero balance (idempotent)
    insert into public.accounts (user_id, account_type, balance)
    values (p_user_id, 'client', 0.00)
    on conflict (user_id) do nothing;
  end if;
end $$;

grant execute on function public.ensure_user_profile_public(
  uuid, text, text, text, text, text, double precision, double precision, jsonb, boolean
) to authenticated;

-- Legacy wrapper kept for backward compatibility
create or replace function public.create_user_profile_public(
  p_user_id uuid,
  p_email text,
  p_name text default '',
  p_phone text default null,
  p_address text default null,
  p_role text default 'client',
  p_lat double precision default null,
  p_lon double precision default null,
  p_address_structured jsonb default null,
  p_is_temp_password boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.ensure_user_profile_public(
    p_user_id => p_user_id,
    p_email => p_email,
    p_name => p_name,
    p_role => p_role,
    p_phone => p_phone,
    p_address => p_address,
    p_lat => p_lat,
    p_lon => p_lon,
    p_address_structured => p_address_structured,
    p_is_temp_password => p_is_temp_password
  );
end $$;

grant execute on function public.create_user_profile_public(
  uuid, text, text, text, text, text, double precision, double precision, jsonb, boolean
) to authenticated;

-- Ensure client profile + account with minimal privileges
create or replace function public.ensure_client_profile_and_account(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
begin
  -- Ensure the base users row exists (noop if already present)
  insert into public.users (id, email, role, created_at, updated_at, email_confirm)
  values (p_user_id, '', 'client', v_now, v_now, false)
  on conflict (id) do update set updated_at = v_now;

  -- Ensure client profile exists
  insert into public.client_profiles (user_id, created_at, updated_at)
  values (p_user_id, v_now, v_now)
  on conflict (user_id) do update set updated_at = v_now;

  -- Ensure a financial account of type 'client' exists
  insert into public.accounts (user_id, account_type, balance)
  values (p_user_id, 'client', 0.00)
  on conflict (user_id) do nothing;
end $$;

grant execute on function public.ensure_client_profile_and_account(uuid) to authenticated;

-- Optional: protect helpers
revoke all on function public._normalize_role(text) from public;
grant execute on function public._normalize_role(text) to postgres; -- keep private
