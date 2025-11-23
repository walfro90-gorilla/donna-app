-- =====================================================================
-- Patch: Ensure user profile RPCs exist and match current schema (no metadata)
-- Date: 2025-10-20
-- Context:
--   - App is calling ensure_user_profile_public (404 Not Found in PostgREST)
--   - Fallback create_user_profile_public fails with: column "metadata" of
--     relation "users" does not exist
--   - Goal: Provide idempotent ensure_... RPC, and replace create_... RPC
--     with a version aligned to public.users current columns (no metadata)
-- =====================================================================

-- Safety: create a stable search_path for SECURITY DEFINER functions
DO $$ BEGIN
  PERFORM 1;
END $$;

-- =====================================================================
-- 1) Idempotent RPC: ensure_user_profile_public
--     - Creates the row in public.users if missing
--     - If exists, updates only provided non-empty fields
--     - Returns JSONB with success/existed
-- =====================================================================
CREATE OR REPLACE FUNCTION public.ensure_user_profile_public(
  p_user_id UUID,
  p_email TEXT,
  p_name TEXT DEFAULT NULL,
  p_role TEXT DEFAULT 'client',
  p_phone TEXT DEFAULT NULL,
  p_address TEXT DEFAULT NULL,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_address_structured JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existed BOOLEAN;
  v_role TEXT;
  v_now TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
  -- Validate that the auth user exists
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User ID does not exist in auth.users';
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.users WHERE id = p_user_id) INTO v_existed;

  -- Normalize role lightly (accept as-is if already canonical)
  v_role := CASE LOWER(COALESCE(p_role, ''))
    WHEN 'usuario' THEN 'client'
    WHEN 'cliente' THEN 'client'
    WHEN 'restaurante' THEN 'restaurant'
    WHEN 'repartidor' THEN 'delivery_agent'
    ELSE COALESCE(NULLIF(TRIM(p_role), ''), 'client')
  END;

  IF NOT v_existed THEN
    -- Insert new profile
    INSERT INTO public.users (
      id, email, name, phone, address, role,
      email_confirm, lat, lon, address_structured,
      created_at, updated_at
    ) VALUES (
      p_user_id,
      p_email,
      NULLIF(p_name, ''),
      NULLIF(p_phone, ''),
      NULLIF(p_address, ''),
      v_role,
      false,
      p_lat,
      p_lon,
      p_address_structured,
      v_now,
      v_now
    );
  ELSE
    -- Update only provided non-empty values; keep existing otherwise
    UPDATE public.users u SET
      email = COALESCE(NULLIF(p_email, ''), u.email),
      name = COALESCE(NULLIF(p_name, ''), u.name),
      phone = COALESCE(NULLIF(p_phone, ''), u.phone),
      address = COALESCE(NULLIF(p_address, ''), u.address),
      role = COALESCE(NULLIF(v_role, ''), u.role),
      lat = COALESCE(p_lat, u.lat),
      lon = COALESCE(p_lon, u.lon),
      address_structured = COALESCE(p_address_structured, u.address_structured),
      updated_at = v_now
    WHERE u.id = p_user_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'existed', v_existed,
    'user_id', p_user_id
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_user_profile_public(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, JSONB
) TO anon, authenticated;

-- =====================================================================
-- 2) Replace create_user_profile_public to match table columns (no metadata)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.create_user_profile_public(
  p_user_id UUID,
  p_email TEXT,
  p_name TEXT,
  p_phone TEXT,
  p_address TEXT,
  p_role TEXT,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_address_structured JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
  v_role TEXT;
BEGIN
  -- Validate auth user
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User ID does not exist in auth.users';
  END IF;

  -- Reject if profile already exists
  IF EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User profile already exists';
  END IF;

  -- Normalize role lightly
  v_role := CASE LOWER(COALESCE(p_role, ''))
    WHEN 'usuario' THEN 'client'
    WHEN 'cliente' THEN 'client'
    WHEN 'restaurante' THEN 'restaurant'
    WHEN 'repartidor' THEN 'delivery_agent'
    ELSE COALESCE(NULLIF(TRIM(p_role), ''), 'client')
  END;

  -- Insert profile
  INSERT INTO public.users (
    id, email, name, phone, address, role,
    email_confirm, lat, lon, address_structured,
    created_at, updated_at
  ) VALUES (
    p_user_id,
    p_email,
    NULLIF(p_name, ''),
    NULLIF(p_phone, ''),
    NULLIF(p_address, ''),
    v_role,
    false,
    p_lat,
    p_lon,
    p_address_structured,
    NOW(),
    NOW()
  );

  v_result := jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'message', 'User profile created successfully'
  );

  RETURN v_result;

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_user_profile_public(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, JSONB
) TO anon, authenticated;

-- =====================================================================
-- 3) Optional helper: set_user_phone_if_missing
--     - Sets users.phone only when empty, returns true if updated
-- =====================================================================
CREATE OR REPLACE FUNCTION public.set_user_phone_if_missing(
  p_user_id UUID,
  p_phone TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated INT;
BEGIN
  UPDATE public.users
  SET phone = NULLIF(p_phone, ''),
      updated_at = NOW()
  WHERE id = p_user_id
    AND (phone IS NULL OR phone = '')
  RETURNING 1 INTO v_updated;

  RETURN COALESCE(v_updated, 0) > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_user_phone_if_missing(UUID, TEXT) TO anon, authenticated;

-- =====================================================================
-- ✅ Done. After running this patch:
--   - ensure_user_profile_public will exist and be callable by anon/authenticated
--   - create_user_profile_public no longer references a non-existent metadata column
--   - set_user_phone_if_missing allows late binding of phone coming from forms
-- =====================================================================
