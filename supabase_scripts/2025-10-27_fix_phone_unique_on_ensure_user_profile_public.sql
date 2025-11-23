-- =====================================================================
-- Patch: Fix duplicate key on users.phone with OAuth signups
-- Date: 2025-10-27
-- Context:
--   - Second Google OAuth user failed with:
--       duplicate key value violates unique constraint "idx_users_phone_unique_not_null"
--   - Root cause: ensure_user_profile_public inserted phone as '' (empty string)
--     which is NOT NULL and therefore hits the unique-partial index when duplicated.
--   - Fix: Insert NULL when phone is empty/blank; only persist E.164 value when provided.
--   - Also sanitize existing rows by turning '' phones into NULL to unblock future inserts.
-- =====================================================================

-- 0) Data sanitation: set phone to NULL where it's an empty string
--    Idempotent and safe to rerun.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'phone'
  ) THEN
    UPDATE public.users
      SET phone = NULL,
          updated_at = NOW()
    WHERE phone = '';
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- Do not block deploy; this is a best-effort sanitation
  NULL;
END $$;

-- 1) Create/Replace RPC with correct NULL handling for phone
CREATE OR REPLACE FUNCTION public.ensure_user_profile_public(
  p_user_id uuid,
  p_email text,
  p_name text DEFAULT '',
  p_role text DEFAULT 'client',
  p_phone text DEFAULT '',
  p_address text DEFAULT '',
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists boolean;
  v_is_email_confirmed boolean := false;
  v_now timestamptz := now();
  v_role text;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id is required';
  END IF;

  -- verify exists in auth.users
  PERFORM 1 FROM auth.users WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User ID % does not exist in auth.users', p_user_id;
  END IF;

  -- email confirmation flag from auth
  SELECT (email_confirmed_at IS NOT NULL) INTO v_is_email_confirmed
  FROM auth.users WHERE id = p_user_id;

  -- normalize role gently
  v_role := CASE LOWER(COALESCE(p_role, ''))
    WHEN 'usuario' THEN 'client'
    WHEN 'cliente' THEN 'client'
    WHEN 'restaurante' THEN 'restaurant'
    WHEN 'repartidor' THEN 'delivery_agent'
    ELSE COALESCE(NULLIF(TRIM(p_role), ''), 'client')
  END;

  -- upsert profile
  SELECT EXISTS(SELECT 1 FROM public.users WHERE id = p_user_id) INTO v_exists;
  IF NOT v_exists THEN
    INSERT INTO public.users (
      id, email, name, phone, address, role, email_confirm,
      lat, lon, address_structured, created_at, updated_at
    ) VALUES (
      p_user_id,
      COALESCE(p_email, ''),
      COALESCE(p_name, ''),
      NULLIF(TRIM(p_phone), ''),           -- IMPORTANT: store NULL, not ''
      COALESCE(p_address, ''),
      COALESCE(v_role, 'client'),
      COALESCE(v_is_email_confirmed, false),
      p_lat,
      p_lon,
      p_address_structured,
      v_now,
      v_now
    );
  ELSE
    UPDATE public.users u SET
      email = COALESCE(NULLIF(p_email, ''), u.email),
      name = COALESCE(NULLIF(p_name, ''), u.name),
      phone = COALESCE(NULLIF(TRIM(p_phone), ''), u.phone),  -- ignore blank -> keep existing
      address = COALESCE(NULLIF(p_address, ''), u.address),
      role = CASE WHEN COALESCE(u.role, '') IN ('', 'client', 'cliente') THEN COALESCE(v_role, 'client') ELSE u.role END,
      email_confirm = COALESCE(u.email_confirm, v_is_email_confirmed),
      lat = COALESCE(p_lat, u.lat),
      lon = COALESCE(p_lon, u.lon),
      address_structured = COALESCE(p_address_structured, u.address_structured),
      updated_at = v_now
    WHERE u.id = p_user_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'data', jsonb_build_object('user_id', p_user_id), 'error', NULL);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_user_profile_public(
  uuid, text, text, text, text, text, double precision, double precision, jsonb
) TO anon, authenticated, service_role;

-- =====================================================================
-- Notes:
-- - This keeps the same signature used by the app and prior scripts.
-- - Phones are now stored as NULL when blank, satisfying unique-partial index
--   patterns like WHERE phone IS NOT NULL.
-- - Provided phone values should already be canonical E.164 (+521234567890); this
--   RPC does not reformat them, it only preserves or ignores blanks.
-- =====================================================================
