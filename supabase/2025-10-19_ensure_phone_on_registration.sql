-- =====================================================================
-- Ensure users.phone is saved when registering via restaurant/delivery forms
-- Minimal-change backend approach: helper + trigger + small RPC hook
-- Safe to run multiple times (CREATE OR REPLACE / IF EXISTS guards)
-- =====================================================================

-- 1) Helper to set phone if missing (prefers explicit param, falls back to auth metadata)
CREATE OR REPLACE FUNCTION public.set_user_phone_if_missing(
  p_user_id UUID,
  p_phone TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone TEXT;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  -- Prefer explicit phone; otherwise use auth.users raw_user_meta_data->>'phone'
  v_phone := NULLIF(btrim(COALESCE(p_phone,
    (SELECT au.raw_user_meta_data->>'phone'
       FROM auth.users au
      WHERE au.id = p_user_id)
  )), '');

  -- Nothing to set
  IF v_phone IS NULL THEN
    RETURN;
  END IF;

  -- Only set if users.phone is NULL or empty
  UPDATE public.users u
     SET phone = v_phone,
         updated_at = NOW()
   WHERE u.id = p_user_id
     AND COALESCE(btrim(u.phone), '') = '';
EXCEPTION WHEN OTHERS THEN
  -- Do not block caller; keep it best-effort
  RAISE NOTICE 'set_user_phone_if_missing: %', SQLERRM;
END;
$$;

-- Optional: allow anon/authenticated to call if needed from RPCs
DO $$
BEGIN
  GRANT EXECUTE ON FUNCTION public.set_user_phone_if_missing(UUID, TEXT) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.set_user_phone_if_missing(UUID, TEXT) TO anon;
EXCEPTION WHEN OTHERS THEN
  -- ignore
END$$;

-- 2) Hook into restaurant creation RPC (only adds a one-line call, keeps existing logic)
--    This version is based on your latest create_restaurant_public signature.
CREATE OR REPLACE FUNCTION public.create_restaurant_public(
  p_user_id UUID,
  p_name TEXT,
  p_status TEXT DEFAULT 'pending',
  p_location_lat DOUBLE PRECISION DEFAULT NULL,
  p_location_lon DOUBLE PRECISION DEFAULT NULL,
  p_location_place_id TEXT DEFAULT NULL,
  p_address TEXT DEFAULT NULL,
  p_address_structured JSONB DEFAULT NULL,
  p_phone TEXT DEFAULT NULL,
  p_online BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_restaurant_id UUID;
  v_result JSONB;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User ID does not exist in auth.users';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User profile does not exist. Create user profile first.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.restaurants WHERE user_id = p_user_id) THEN
    RAISE EXCEPTION 'Restaurant already exists for this user';
  END IF;

  -- Ensure role is set to restaurant (existing behavior from your fix)
  UPDATE public.users
     SET role = 'restaurant',
         updated_at = NOW()
   WHERE id = p_user_id AND COALESCE(role, '') <> 'restaurant';

  -- NEW: Ensure users.phone is populated (only if missing)
  PERFORM public.set_user_phone_if_missing(p_user_id, p_phone);

  -- Insert restaurant as usual
  INSERT INTO public.restaurants (
    user_id,
    name,
    status,
    location_lat,
    location_lon,
    location_place_id,
    address,
    address_structured,
    phone,
    online,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_name,
    p_status,
    p_location_lat,
    p_location_lon,
    p_location_place_id,
    p_address,
    p_address_structured,
    p_phone,
    p_online,
    NOW(),
    NOW()
  )
  RETURNING id INTO v_restaurant_id;

  v_result := jsonb_build_object(
    'success', true,
    'restaurant_id', v_restaurant_id,
    'message', 'Restaurant created successfully'
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

-- 3) Trigger on delivery_agent_profiles to backfill phone from auth metadata (no app changes)
--    Works because the sign-up stored metadata.phone in auth.users
CREATE OR REPLACE FUNCTION public.trg_set_user_phone_from_metadata()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.set_user_phone_if_missing(NEW.user_id, NULL);
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  -- Drop old trigger if exists to keep idempotence
  IF EXISTS (
    SELECT 1
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
     WHERE c.relname = 'delivery_agent_profiles'
       AND t.tgname = 'trg_after_upsert_set_phone'
  ) THEN
    DROP TRIGGER trg_after_upsert_set_phone ON public.delivery_agent_profiles;
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- ignore
END$$;

CREATE TRIGGER trg_after_upsert_set_phone
AFTER INSERT OR UPDATE ON public.delivery_agent_profiles
FOR EACH ROW
EXECUTE FUNCTION public.trg_set_user_phone_from_metadata();

-- 4) Optional one-time backfill for existing users with empty phone (commented)
-- UPDATE public.users u
--    SET phone = COALESCE(NULLIF(btrim(u.phone), ''), au.raw_user_meta_data->>'phone'),
--        updated_at = NOW()
--   FROM auth.users au
--  WHERE u.id = au.id
--    AND COALESCE(btrim(u.phone), '') = ''
--    AND NULLIF(btrim(au.raw_user_meta_data->>'phone'), '') IS NOT NULL;

-- =====================================================================
-- End of script
-- =====================================================================
