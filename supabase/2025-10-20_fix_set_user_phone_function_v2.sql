-- =====================================================================
-- Patch: Resolve return-type conflict for set_user_phone_if_missing
-- Date: 2025-10-20
-- Why:
--   You saw: "cannot change return type of existing function" when a script
--   tried to CREATE OR REPLACE set_user_phone_if_missing(UUID, TEXT)
--   with a different return type. PostgreSQL requires dropping first, which
--   we want to avoid to keep backward compatibility.
-- What this patch does:
--   - Adds a versioned function set_user_phone_if_missing_v2(UUID, TEXT)
--     that returns BOOLEAN (updated?) and contains robust logic
--   - Adds a safe shim set_user_phone_if_missing_safe(UUID, TEXT) RETURNS VOID
--     that calls whichever version is present, without errors
--   - Grants execute to anon/authenticated
-- How to use:
--   - Do NOT drop the existing set_user_phone_if_missing
--   - Prefer calling ..._v2 in new code or ..._safe in triggers/RPCs
--   - This avoids any return-type collisions
-- =====================================================================

-- 1) Versioned helper that reports whether an update occurred
CREATE OR REPLACE FUNCTION public.set_user_phone_if_missing_v2(
  p_user_id UUID,
  p_phone   TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone   TEXT;
  v_updated INT;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Prefer explicit phone; otherwise use auth.users raw_user_meta_data->>'phone'
  v_phone := NULLIF(btrim(COALESCE(p_phone,
    (SELECT au.raw_user_meta_data->>'phone'
       FROM auth.users au
      WHERE au.id = p_user_id)
  )), '');

  IF v_phone IS NULL THEN
    RETURN FALSE;
  END IF;

  UPDATE public.users u
     SET phone = v_phone,
         updated_at = NOW()
   WHERE u.id = p_user_id
     AND COALESCE(btrim(u.phone), '') = ''
  RETURNING 1 INTO v_updated;

  RETURN COALESCE(v_updated, 0) > 0;
EXCEPTION WHEN OTHERS THEN
  -- Do not block callers; just log and return false
  RAISE NOTICE 'set_user_phone_if_missing_v2: %', SQLERRM;
  RETURN FALSE;
END;
$$;

DO $$
BEGIN
  GRANT EXECUTE ON FUNCTION public.set_user_phone_if_missing_v2(UUID, TEXT) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.set_user_phone_if_missing_v2(UUID, TEXT) TO anon;
EXCEPTION WHEN OTHERS THEN
  -- ignore
END $$;

-- 2) Safe shim that never raises due to missing/return-type mismatches
--    It tries the legacy name first; if not present, calls v2.
CREATE OR REPLACE FUNCTION public.set_user_phone_if_missing_safe(
  p_user_id UUID,
  p_phone   TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  BEGIN
    -- Call legacy function if present (works regardless of its return type)
    PERFORM public.set_user_phone_if_missing(p_user_id, p_phone);
    RETURN;
  EXCEPTION
    WHEN undefined_function THEN
      -- Fallback to v2 if legacy is not defined
      PERFORM public.set_user_phone_if_missing_v2(p_user_id, p_phone);
      RETURN;
    WHEN OTHERS THEN
      -- If legacy exists but fails, do not block; try v2 as best-effort
      RAISE NOTICE 'legacy set_user_phone_if_missing failed: %', SQLERRM;
      PERFORM public.set_user_phone_if_missing_v2(p_user_id, p_phone);
      RETURN;
  END;
END;
$$;

DO $$
BEGIN
  GRANT EXECUTE ON FUNCTION public.set_user_phone_if_missing_safe(UUID, TEXT) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.set_user_phone_if_missing_safe(UUID, TEXT) TO anon;
EXCEPTION WHEN OTHERS THEN
  -- ignore
END $$;

-- Optional: You may later update triggers/RPCs to call ..._safe or ..._v2,
-- but this patch alone is sufficient to avoid the return-type conflict.

-- =====================================================================
-- End of patch
-- =====================================================================
