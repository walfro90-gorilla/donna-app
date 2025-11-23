-- =============================================================
-- Registration & Profile RPCs bootstrap (idempotent, SECURITY DEFINER)
-- Creates/repairs the RPCs used by the app during signup/registration.
-- Standard response: { success, data, error }
-- =============================================================

-- 0) Safe drops for legacy signatures to avoid overload conflicts
DO $$
BEGIN
  -- ensure_user_profile_public legacy signature
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'ensure_user_profile_public'
      AND pg_get_function_identity_arguments(p.oid) = 'p_user_id uuid, p_email text, p_name text, p_role text'
  ) THEN
    EXECUTE 'DROP FUNCTION public.ensure_user_profile_public(uuid, text, text, text)';
  END IF;

  -- create_user_profile_public legacy signature (no JSON address)
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'create_user_profile_public'
      AND pg_get_function_identity_arguments(p.oid) = 'p_user_id uuid, p_email text, p_name text, p_phone text, p_address text, p_role text, p_lat double precision, p_lon double precision, p_address_structured jsonb'
  ) THEN
    -- keep this one if already modern; do nothing
    NULL;
  ELSIF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'create_user_profile_public'
  ) THEN
    -- drop any other mismatched signature to recreate a standard one
    EXECUTE 'DROP FUNCTION public.create_user_profile_public';
  END IF;
END $$;

-- 1) ensure_user_profile_public (extended signature, idempotent)
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
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id is required';
  END IF;

  -- verify exists in auth.users
  PERFORM 1 FROM auth.users WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User ID % does not exist in auth.users', p_user_id;
  END IF;

  -- derive email confirmation from auth
  SELECT (email_confirmed_at IS NOT NULL) INTO v_is_email_confirmed
  FROM auth.users WHERE id = p_user_id;

  -- upsert profile minimally
  SELECT EXISTS(SELECT 1 FROM public.users WHERE id = p_user_id) INTO v_exists;
  IF NOT v_exists THEN
    INSERT INTO public.users (
      id, email, name, phone, address, role, email_confirm, lat, lon, address_structured, created_at, updated_at
    ) VALUES (
      p_user_id,
      COALESCE(p_email, ''),
      COALESCE(p_name, ''),
      COALESCE(p_phone, ''),
      COALESCE(p_address, ''),
      COALESCE(p_role, 'client'),
      COALESCE(v_is_email_confirmed, false),
      p_lat,
      p_lon,
      p_address_structured,
      v_now,
      v_now
    );
  ELSE
    UPDATE public.users SET
      email = COALESCE(NULLIF(p_email, ''), email),
      name = COALESCE(NULLIF(p_name, ''), name),
      phone = COALESCE(NULLIF(p_phone, ''), phone),
      address = COALESCE(NULLIF(p_address, ''), address),
      -- only normalize role if current role is empty/client/cliente
      role = CASE WHEN COALESCE(role, '') IN ('', 'client', 'cliente') THEN COALESCE(p_role, 'client') ELSE role END,
      email_confirm = COALESCE(email_confirm, v_is_email_confirmed),
      lat = COALESCE(p_lat, lat),
      lon = COALESCE(p_lon, lon),
      address_structured = COALESCE(p_address_structured, address_structured),
      updated_at = v_now
    WHERE id = p_user_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'data', jsonb_build_object('user_id', p_user_id), 'error', NULL);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_user_profile_public(uuid, text, text, text, text, text, double precision, double precision, jsonb) TO anon, authenticated, service_role;

-- 1.b) ensure_user_profile_v2 wrapper (keeps clients compatible)
CREATE OR REPLACE FUNCTION public.ensure_user_profile_v2(
  p_user_id uuid,
  p_email text,
  p_role text DEFAULT 'client',
  p_name text DEFAULT '',
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
BEGIN
  RETURN public.ensure_user_profile_public(
    p_user_id => p_user_id,
    p_email => p_email,
    p_name => p_name,
    p_role => p_role,
    p_phone => p_phone,
    p_address => p_address,
    p_lat => p_lat,
    p_lon => p_lon,
    p_address_structured => p_address_structured
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_user_profile_v2(uuid, text, text, text, text, text, double precision, double precision, jsonb) TO anon, authenticated, service_role;

-- 2) create_user_profile_public (non-idempotent by name, but implemented via ensure to avoid legacy errors)
CREATE OR REPLACE FUNCTION public.create_user_profile_public(
  p_user_id uuid,
  p_email text,
  p_name text,
  p_phone text,
  p_address text,
  p_role text,
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL,
  p_is_temp_password boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res jsonb;
BEGIN
  -- Route to ensure function to avoid schema mismatches like missing 'metadata' column
  v_res := public.ensure_user_profile_public(
    p_user_id => p_user_id,
    p_email => p_email,
    p_name => p_name,
    p_role => p_role,
    p_phone => p_phone,
    p_address => p_address,
    p_lat => p_lat,
    p_lon => p_lon,
    p_address_structured => p_address_structured
  );
  RETURN v_res;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_user_profile_public(uuid, text, text, text, text, text, double precision, double precision, jsonb, boolean) TO anon, authenticated, service_role;

-- 3) create_restaurant_public (idempotent on user_id)
CREATE OR REPLACE FUNCTION public.create_restaurant_public(
  p_user_id uuid,
  p_name text,
  p_status text DEFAULT 'pending',
  p_location_lat double precision DEFAULT NULL,
  p_location_lon double precision DEFAULT NULL,
  p_location_place_id text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_online boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_restaurant_id uuid;
BEGIN
  -- validate auth user
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User ID does not exist in auth.users';
  END IF;

  -- ensure user profile exists
  PERFORM public.ensure_user_profile_public(p_user_id, COALESCE(p_name,'')||'@placeholder.local', p_name, 'restaurant');

  -- if already exists, return it
  SELECT id INTO v_restaurant_id FROM public.restaurants WHERE user_id = p_user_id LIMIT 1;
  IF v_restaurant_id IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'data', jsonb_build_object('restaurant_id', v_restaurant_id), 'error', NULL);
  END IF;

  INSERT INTO public.restaurants (
    user_id, name, status, location_lat, location_lon, location_place_id, address, address_structured, phone, online, created_at, updated_at
  ) VALUES (
    p_user_id, p_name, p_status, p_location_lat, p_location_lon, p_location_place_id, p_address, p_address_structured, p_phone, COALESCE(p_online,false), now(), now()
  ) RETURNING id INTO v_restaurant_id;

  -- Optionally normalize user role to restaurant if previously client/empty
  UPDATE public.users SET role = 'restaurant', updated_at = now()
  WHERE id = p_user_id AND COALESCE(role,'') IN ('', 'client', 'cliente');

  RETURN jsonb_build_object('success', true, 'data', jsonb_build_object('restaurant_id', v_restaurant_id), 'error', NULL);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_restaurant_public(uuid, text, text, double precision, double precision, text, text, jsonb, text, boolean) TO anon, authenticated, service_role;

-- 4) create_account_public (idempotent on user_id + account_type)
CREATE OR REPLACE FUNCTION public.create_account_public(
  p_user_id uuid,
  p_account_type text,
  p_balance numeric DEFAULT 0.00
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User ID does not exist in auth.users';
  END IF;

  -- Upsert by (user_id, account_type)
  INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
  VALUES (p_user_id, p_account_type, COALESCE(p_balance,0.0), now(), now())
  ON CONFLICT (user_id, account_type) DO UPDATE
    SET updated_at = EXCLUDED.updated_at
  RETURNING id INTO v_account_id;

  RETURN jsonb_build_object('success', true, 'data', jsonb_build_object('account_id', v_account_id), 'error', NULL);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_account_public(uuid, text, numeric) TO anon, authenticated, service_role;

-- 5) register_restaurant_v2 (atomic orchestrator)
CREATE OR REPLACE FUNCTION public.register_restaurant_v2(
  p_user_id uuid,
  p_email text,
  p_restaurant_name text,
  p_phone text DEFAULT '',
  p_address text DEFAULT '',
  p_location_lat double precision DEFAULT NULL,
  p_location_lon double precision DEFAULT NULL,
  p_location_place_id text DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_restaurant_id uuid;
  v_account_id uuid;
BEGIN
  -- 1) ensure user profile
  PERFORM public.ensure_user_profile_public(
    p_user_id => p_user_id,
    p_email => p_email,
    p_name => COALESCE(p_restaurant_name, ''),
    p_role => 'restaurant',
    p_phone => p_phone,
    p_address => p_address,
    p_lat => p_location_lat,
    p_lon => p_location_lon,
    p_address_structured => p_address_structured
  );

  -- 2) create restaurant if missing
  SELECT id INTO v_restaurant_id FROM public.restaurants WHERE user_id = p_user_id LIMIT 1;
  IF v_restaurant_id IS NULL THEN
    INSERT INTO public.restaurants (
      user_id, name, status, location_lat, location_lon, location_place_id, address, address_structured, phone, online, created_at, updated_at
    ) VALUES (
      p_user_id, p_restaurant_name, 'pending', p_location_lat, p_location_lon, p_location_place_id, p_address, p_address_structured, p_phone, false, now(), now()
    ) RETURNING id INTO v_restaurant_id;
  END IF;

  -- 3) ensure financial account for restaurant
  INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
  VALUES (p_user_id, 'restaurant', 0.0, now(), now())
  ON CONFLICT (user_id, account_type) DO UPDATE
    SET updated_at = EXCLUDED.updated_at
  RETURNING id INTO v_account_id;

  -- 4) normalize role to restaurant if needed
  UPDATE public.users SET role = 'restaurant', updated_at = now()
  WHERE id = p_user_id AND COALESCE(role,'') IN ('', 'client', 'cliente');

  RETURN jsonb_build_object(
    'success', true,
    'data', jsonb_build_object('user_id', p_user_id, 'restaurant_id', v_restaurant_id, 'account_id', v_account_id),
    'error', NULL
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_restaurant_v2(uuid, text, text, text, text, double precision, double precision, text, jsonb) TO anon, authenticated, service_role;

-- 6) Helper: set_user_phone_if_missing
CREATE OR REPLACE FUNCTION public.set_user_phone_if_missing(p_user_id uuid, p_phone text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated boolean := false;
BEGIN
  UPDATE public.users SET phone = p_phone, updated_at = now()
  WHERE id = p_user_id AND (phone IS NULL OR phone = '');
  -- FOUND is true if the previous SQL statement affected at least one row
  v_updated := FOUND;
  RETURN jsonb_build_object('success', true, 'data', jsonb_build_object('updated', v_updated), 'error', NULL);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_user_phone_if_missing(uuid, text) TO anon, authenticated, service_role;

-- 7) Quick sanity: list signatures (optional)
-- SELECT p.proname, pg_get_function_identity_arguments(p.oid) args, p.prosecdef
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND p.proname IN (
--   'ensure_user_profile_public','ensure_user_profile_v2','create_user_profile_public',
--   'create_restaurant_public','create_account_public','register_restaurant_v2','set_user_phone_if_missing'
-- ) ORDER BY 1;
