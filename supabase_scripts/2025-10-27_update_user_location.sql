-- =============================================================
-- RPC: update_user_location
-- Purpose: Update current user's delivery address and coordinates
-- Notes:
--  - Sets address, lat, lon, address_structured, updated_at
--  - If PostGIS and current_location column exist, sets geography(Point,4326)
--  - Only allows updating the row of auth.uid()
-- =============================================================
create or replace function public.update_user_location(
  p_address text,
  p_lat double precision,
  p_lon double precision,
  p_address_structured jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Update canonical fields
  update public.users
  set
    address = nullif(btrim(coalesce(p_address, '')), ''),
    lat = p_lat,
    lon = p_lon,
    address_structured = coalesce(p_address_structured, address_structured),
    updated_at = now()
  where id = auth.uid();

  -- Optionally set current_location if PostGIS and column exist
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

-- Permissions: allow authenticated users to execute
grant execute on function public.update_user_location(text, double precision, double precision, jsonb) to authenticated;
