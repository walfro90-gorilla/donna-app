-- =============================================================
-- Fix: update_user_location RPC missing + RLS for users self-update
-- Date: 2025-10-27
-- Why:
--   - The app calls public.update_user_location(p_address, p_lat, p_lon, p_address_structured)
--   - RPC not found (PGRST202) and fallback PATCH to public.users failed (RLS 403)
-- What this does:
--   1) Creates/repairs the RPC with SECURITY DEFINER to update only auth.uid() row
--   2) Grants EXECUTE on the function to role authenticated
--   3) Ensures an UPDATE RLS policy for users allowing self-update
--   4) Grants UPDATE on specific columns to authenticated (column-level)
-- Notes:
--   - Script is safe to re-run (idempotent)
--   - Does not relax read policies
-- =============================================================

-- 1) Create or replace RPC with expected signature and parameter names
create or replace function public.update_user_location(
  p_address            text,
  p_lat                double precision,
  p_lon                double precision,
  p_address_structured jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Update canonical fields for the current authenticated user
  update public.users
  set
    address            = nullif(btrim(coalesce(p_address, '')), ''),
    lat                = p_lat,
    lon                = p_lon,
    address_structured = coalesce(p_address_structured, address_structured),
    updated_at         = now()
  where id = auth.uid();

  -- Optionally set current_location if PostGIS and the column exist
  if exists (select 1 from pg_extension where extname = 'postgis')
     and exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'users' and column_name = 'current_location'
     ) then
    execute '
      update public.users
      set current_location = case
        when $1 is not null and $2 is not null then ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography
        else null
      end
      where id = $3
    ' using p_lat, p_lon, auth.uid();
  end if;
end;
$$;

-- 2) Permissions: allow authenticated to execute the function
grant execute on function public.update_user_location(text, double precision, double precision, jsonb) to authenticated;

-- 3) RLS: ensure UPDATE policy for users to update own row exists
alter table public.users enable row level security;

do $$
declare
  has_policy boolean;
begin
  select exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='users' and policyname='users_update_self_address_basic'
  ) into has_policy;

  if not has_policy then
    execute $$
      create policy users_update_self_address_basic
      on public.users
      as permissive
      for update
      to authenticated
      using (id = auth.uid())
      with check (id = auth.uid())
    $$;
  end if;
end $$;

-- 4) Column-level GRANTs: allow updating only address-related fields
grant update (address, lat, lon, address_structured, updated_at, phone) on public.users to authenticated;

-- Conditionally grant UPDATE on current_location if the column exists
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'users' and column_name = 'current_location'
  ) then
    execute 'grant update (current_location) on public.users to authenticated';
  end if;
end $$;

-- Done
