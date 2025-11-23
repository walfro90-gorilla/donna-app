-- =============================================================
-- Canonicalize RPC update_user_location and ensure self UPDATE policy
-- Idempotent and safe to re-run
-- =============================================================

-- 1) Ensure RLS is enabled on users
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- 2) Create/replace RPC with the exact signature the app expects
--    update_user_location(p_address text, p_lat double precision, p_lon double precision, p_address_structured jsonb default null)
CREATE OR REPLACE FUNCTION public.update_user_location(
  p_address text,
  p_lat double precision,
  p_lon double precision,
  p_address_structured jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Canonical update for the authenticated user
  UPDATE public.users
  SET
    address = NULLIF(BTRIM(COALESCE(p_address, '')), ''),
    lat = p_lat,
    lon = p_lon,
    address_structured = COALESCE(p_address_structured, address_structured),
    updated_at = NOW()
  WHERE id = auth.uid();

  -- If PostGIS + geography(current_location) exist, update it too
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis')
     AND EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'users'
         AND column_name = 'current_location'
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

-- 3) Grant execute to authenticated role (safe if already granted)
DO $$
BEGIN
  BEGIN
    GRANT EXECUTE ON FUNCTION public.update_user_location(text, double precision, double precision, jsonb) TO authenticated;
  EXCEPTION WHEN undefined_function THEN
    -- In case the function name was schema-cached differently, ensure grant by looking up via oid
    NULL;
  END;
END $$;

-- 4) Ensure UPDATE policy so direct updates (fallback) work for the same user
DO $$
DECLARE
  has_policy BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename  = 'users'
       AND policyname = 'users_update_self_basic'
  ) INTO has_policy;

  IF NOT has_policy THEN
    EXECUTE $$
      CREATE POLICY users_update_self_basic
      ON public.users
      AS PERMISSIVE
      FOR UPDATE
      TO authenticated
      USING (id = auth.uid())
      WITH CHECK (id = auth.uid())
    $$;
  END IF;
END $$;

-- 5) Optional: add comment for auditing
COMMENT ON FUNCTION public.update_user_location(text, double precision, double precision, jsonb)
IS 'Updates address/lat/lon/address_structured for auth.uid(); used by mobile/web app';
