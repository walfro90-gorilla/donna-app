-- =============================================================
-- Fix v2: update_user_location RPC + self-update RLS without DO/EXECUTE for CREATE POLICY
-- Date: 2025-10-27
-- Context:
--   Previous script failed at CREATE POLICY inside DO $$ ... $$ block.
--   This version moves policy DDL to top-level statements.
-- What this does (idempotent):
--   1) Creates/Replaces RPC public.update_user_location(p_address text, p_lat double precision, p_lon double precision, p_address_structured jsonb)
--   2) Grants EXECUTE to role authenticated
--   3) Enables RLS on public.users
--   4) Drops conflicting self-update policy names if exist; creates a single canonical policy
--   5) Grants column-level UPDATE to authenticated (and conditionally current_location)
-- =============================================================

-- 1) Create or replace RPC with expected signature and behavior
CREATE OR REPLACE FUNCTION public.update_user_location(
  p_address            text,
  p_lat                double precision,
  p_lon                double precision,
  p_address_structured jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Update canonical fields for the current authenticated user
  UPDATE public.users
  SET
    address            = NULLIF(BTRIM(COALESCE(p_address, '')), ''),
    lat                = p_lat,
    lon                = p_lon,
    address_structured = COALESCE(p_address_structured, address_structured),
    updated_at         = NOW()
  WHERE id = auth.uid();

  -- Optionally set current_location if PostGIS and the column exist
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis')
     AND EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'current_location'
     ) THEN
    EXECUTE '
      UPDATE public.users
      SET current_location = CASE
        WHEN $1 IS NOT NULL AND $2 IS NOT NULL THEN ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography
        ELSE NULL
      END
      WHERE id = $3
    ' USING p_lat, p_lon, auth.uid();
  END IF;
END;
$$;

-- 2) Permissions: allow authenticated to execute the function
GRANT EXECUTE ON FUNCTION public.update_user_location(text, double precision, double precision, jsonb) TO authenticated;

-- 3) Ensure RLS is enabled on users table
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- 4) Self-update policy: drop old/conflicting names and create one canonical policy
DROP POLICY IF EXISTS users_update_self_address_basic ON public.users;
DROP POLICY IF EXISTS users_update_self_basic ON public.users;

CREATE POLICY users_update_self_basic
ON public.users
AS PERMISSIVE
FOR UPDATE
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- 5) Column-level GRANTs: allow updating only address-related fields
GRANT UPDATE (address, lat, lon, address_structured, updated_at, phone) ON public.users TO authenticated;

-- Conditionally grant UPDATE on current_location if the column exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'current_location'
  ) THEN
    EXECUTE 'GRANT UPDATE (current_location) ON public.users TO authenticated';
  END IF;
END $$;

-- End of script
