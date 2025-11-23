-- =============================================
-- Client Address RPCs and Helpers (SECURITY DEFINER)
-- Aligns app with new schema using public.client_profiles
-- =============================================

-- Safety: drop incompatible signatures to avoid 42P13 when return types changed in past
drop function if exists public.ensure_client_profile_and_account(uuid);
drop function if exists public.update_client_default_address(uuid, text, double precision, double precision, jsonb);
drop function if exists public.update_user_location(text, double precision, double precision, jsonb);

-- Helper: ensure client_profiles row and financial account for a user
-- Keep return type jsonb to match existing deployments and avoid 42P13 errors
create or replace function public.ensure_client_profile_and_account(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Ensure client_profiles row
  insert into public.client_profiles as cp (user_id, updated_at)
  values (p_user_id, now())
  on conflict (user_id) do update set updated_at = excluded.updated_at;

  -- Ensure accounts row of type 'client'
  insert into public.accounts as a (user_id, account_type, balance)
  values (p_user_id, 'client', 0.00)
  on conflict (user_id) do nothing;

  return jsonb_build_object('success', true);
end;
$$;

comment on function public.ensure_client_profile_and_account(uuid) is 'Ensures client_profiles row and client financial account exist for given user_id';
grant execute on function public.ensure_client_profile_and_account(uuid) to anon, authenticated, service_role;

-- Main: update default client address (writes into client_profiles)
create or replace function public.update_client_default_address(
  p_user_id uuid,
  p_address text default null,
  p_lat double precision default null,
  p_lon double precision default null,
  p_address_structured jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  perform public.ensure_client_profile_and_account(p_user_id);

  update public.client_profiles
  set
    address = coalesce(p_address, address),
    lat = coalesce(p_lat, lat),
    lon = coalesce(p_lon, lon),
    address_structured = coalesce(p_address_structured, address_structured),
    updated_at = now()
  where user_id = p_user_id;

  select jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'address', (select address from public.client_profiles where user_id = p_user_id),
    'lat', (select lat from public.client_profiles where user_id = p_user_id),
    'lon', (select lon from public.client_profiles where user_id = p_user_id)
  ) into v_result;

  return v_result;
exception when others then
  return jsonb_build_object('success', false, 'error', sqlerrm);
end;
$$;

comment on function public.update_client_default_address(uuid, text, double precision, double precision, jsonb)
is 'Updates default address/lat/lon/address_structured for a client in client_profiles';
grant execute on function public.update_client_default_address(uuid, text, double precision, double precision, jsonb) to authenticated, service_role;

-- Optional: Backward-compat wrapper to old name used in app (if exists)
create or replace function public.update_user_location(
  p_address text default null,
  p_lat double precision default null,
  p_lon double precision default null,
  p_address_structured jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  -- uses auth.uid() to determine user
  return public.update_client_default_address(
    auth.uid(), p_address, p_lat, p_lon, p_address_structured
  );
end;
$$;

grant execute on function public.update_user_location(text, double precision, double precision, jsonb) to authenticated, service_role;

-- Index helpers (safe)
create index if not exists idx_client_profiles_user_id on public.client_profiles(user_id);
create index if not exists idx_client_profiles_lat_lon on public.client_profiles(lat, lon);
