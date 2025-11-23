-- ============================================================================
-- Robust, transactional Restaurant Registration (v2) with structured logging
-- Safe to apply alongside existing functions. Does NOT drop or alter old RPCs.
--
-- What this provides
-- 1) app_logs table + app_log() helper for structured logs
-- 2) ensure_user_profile_v2()  -> creates/updates public.users without using metadata
-- 3) ensure_account_v2()       -> ensures a financial account for user
-- 4) register_restaurant_v2()  -> single orchestration RPC (profile + restaurant + account)
--    All SECURITY DEFINER and RLS-safe. Adds granular RAISE NOTICE and app_logs rows.
--
-- After running:
-- - Update the app to call register_restaurant_v2 from the registration form.
-- - Old RPCs (create_user_profile_public, create_restaurant_public, create_account_public)
--   remain untouched and can be retired later.
-- ============================================================================

-- 0) Prereqs: extensions commonly used in Supabase
-- (gen_random_uuid() from pgcrypto)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1) Structured logging sink (non-critical)
CREATE TABLE IF NOT EXISTS public.app_logs (
  id           bigserial PRIMARY KEY,
  at           timestamptz NOT NULL DEFAULT now(),
  scope        text        NOT NULL,
  message      text        NOT NULL,
  data         jsonb,
  created_by   text        DEFAULT current_user
);

COMMENT ON TABLE public.app_logs IS 'Lightweight application logs for debugging flows';

CREATE OR REPLACE FUNCTION public.app_log(
  p_scope   text,
  p_message text,
  p_data    jsonb DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.app_logs(scope, message, data)
  VALUES (p_scope, p_message, p_data);
EXCEPTION WHEN OTHERS THEN
  -- Never block main transaction due to logging errors
  NULL;
END;
$$;

GRANT INSERT, SELECT ON TABLE public.app_logs TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_log(text, text, jsonb) TO anon, authenticated;

-- 2) Ensure/Upsert user profile in public.users (no metadata column usage)
CREATE OR REPLACE FUNCTION public.ensure_user_profile_v2(
  p_user_id            uuid,
  p_email              text,
  p_role               text DEFAULT 'client',
  p_name               text DEFAULT '',
  p_phone              text DEFAULT '',
  p_address            text DEFAULT '',
  p_lat                double precision DEFAULT NULL,
  p_lon                double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existed boolean := false;
  v_role text;
BEGIN
  PERFORM public.app_log('ensure_user_profile_v2', 'start', jsonb_build_object(
    'user_id', p_user_id,
    'email', p_email,
    'role', p_role
  ));

  -- Normalize role
  v_role := lower(coalesce(p_role, 'client'));
  IF v_role NOT IN ('client','restaurant','delivery_agent','admin') THEN
    v_role := 'client';
  END IF;

  -- Upsert-like behavior without ON CONFLICT to keep broad compatibility
  IF EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    v_existed := true;
    UPDATE public.users SET
      email = COALESCE(email, p_email),
      name = CASE WHEN COALESCE(p_name,'') <> '' THEN p_name ELSE name END,
      phone = CASE WHEN (phone IS NULL OR phone = '') AND COALESCE(p_phone,'') <> '' THEN p_phone ELSE phone END,
      address = CASE WHEN COALESCE(p_address,'') <> '' THEN p_address ELSE address END,
      role = COALESCE(role, v_role),
      lat = COALESCE(lat, p_lat),
      lon = COALESCE(lon, p_lon),
      address_structured = COALESCE(address_structured, p_address_structured),
      updated_at = now()
    WHERE id = p_user_id;
  ELSE
    INSERT INTO public.users (
      id, email, name, phone, address, role, email_confirm,
      lat, lon, address_structured, created_at, updated_at
    ) VALUES (
      p_user_id,
      p_email,
      COALESCE(p_name,''),
      NULLIF(p_phone,''),
      NULLIF(p_address,''),
      v_role,
      false,
      p_lat,
      p_lon,
      p_address_structured,
      now(), now()
    );
  END IF;

  PERFORM public.app_log('ensure_user_profile_v2', 'done', jsonb_build_object('existed', v_existed));
  RETURN json_build_object('success', true, 'existed', v_existed, 'user_id', p_user_id);

EXCEPTION WHEN OTHERS THEN
  PERFORM public.app_log('ensure_user_profile_v2', 'error', jsonb_build_object('err', SQLERRM));
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_user_profile_v2(
  uuid, text, text, text, text, text, double precision, double precision, jsonb
) TO anon, authenticated;

-- 3) Ensure a financial account exists
CREATE OR REPLACE FUNCTION public.ensure_account_v2(
  p_user_id uuid,
  p_account_type text
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_id uuid;
  v_type text := lower(p_account_type);
BEGIN
  IF v_type NOT IN ('client','restaurant','delivery_agent','admin') THEN
    v_type := 'client';
  END IF;

  PERFORM public.app_log('ensure_account_v2', 'start', jsonb_build_object('user_id', p_user_id, 'type', v_type));

  SELECT id INTO v_account_id FROM public.accounts WHERE user_id = p_user_id;
  IF v_account_id IS NULL THEN
    INSERT INTO public.accounts(id, user_id, account_type, balance, created_at, updated_at)
    VALUES (gen_random_uuid(), p_user_id, v_type, 0.00, now(), now())
    RETURNING id INTO v_account_id;
  END IF;

  PERFORM public.app_log('ensure_account_v2', 'done', jsonb_build_object('account_id', v_account_id));
  RETURN json_build_object('success', true, 'account_id', v_account_id);

EXCEPTION WHEN OTHERS THEN
  PERFORM public.app_log('ensure_account_v2', 'error', jsonb_build_object('err', SQLERRM));
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_account_v2(uuid, text) TO anon, authenticated;

-- 4) Orchestrator: register restaurant in a single, idempotent-like transaction
CREATE OR REPLACE FUNCTION public.register_restaurant_v2(
  p_user_id            uuid,
  p_email              text,
  p_restaurant_name    text,
  p_phone              text DEFAULT '',
  p_address            text DEFAULT '',
  p_location_lat       double precision,
  p_location_lon       double precision,
  p_location_place_id  text DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_result json;
  v_acc_result json;
  v_restaurant_id uuid;
BEGIN
  PERFORM public.app_log('register_restaurant_v2', 'start', jsonb_build_object(
    'user_id', p_user_id,
    'email', p_email,
    'restaurant', p_restaurant_name
  ));

  -- 4.1 Ensure user profile with role = restaurant
  v_user_result := public.ensure_user_profile_v2(
    p_user_id,
    p_email,
    'restaurant',
    p_restaurant_name,
    p_phone,
    p_address,
    p_location_lat,
    p_location_lon,
    p_address_structured
  );
  IF COALESCE((v_user_result->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'ensure_user_profile_v2 failed: %', v_user_result->>'error';
  END IF;

  -- 4.2 Ensure restaurant row exists
  SELECT id INTO v_restaurant_id FROM public.restaurants WHERE user_id = p_user_id;
  IF v_restaurant_id IS NULL THEN
    INSERT INTO public.restaurants (
      id, user_id, name, status, location_lat, location_lon, location_place_id,
      address, address_structured, phone, online, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), p_user_id, p_restaurant_name, 'pending',
      p_location_lat, p_location_lon, p_location_place_id,
      p_address, p_address_structured, NULLIF(p_phone,''), false,
      now(), now()
    ) RETURNING id INTO v_restaurant_id;
  END IF;
  PERFORM public.app_log('register_restaurant_v2', 'restaurant_ready', jsonb_build_object('restaurant_id', v_restaurant_id));

  -- 4.3 Ensure financial account (restaurant)
  v_acc_result := public.ensure_account_v2(p_user_id, 'restaurant');
  IF COALESCE((v_acc_result->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'ensure_account_v2 failed: %', v_acc_result->>'error';
  END IF;

  PERFORM public.app_log('register_restaurant_v2', 'done', jsonb_build_object(
    'restaurant_id', v_restaurant_id,
    'account_id', v_acc_result->>'account_id'
  ));

  RETURN json_build_object(
    'success', true,
    'user_id', p_user_id,
    'restaurant_id', v_restaurant_id,
    'account_id', v_acc_result->>'account_id'
  );

EXCEPTION WHEN OTHERS THEN
  PERFORM public.app_log('register_restaurant_v2', 'error', jsonb_build_object('err', SQLERRM));
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_restaurant_v2(
  uuid, text, text, text, text, double precision, double precision, text, jsonb
) TO anon, authenticated;

-- Optional: quick introspection helpers
COMMENT ON FUNCTION public.ensure_user_profile_v2(uuid, text, text, text, text, text, double precision, double precision, jsonb)
  IS 'Idempotent user profile ensure for public.users (no metadata dependency)';
COMMENT ON FUNCTION public.ensure_account_v2(uuid, text)
  IS 'Ensures a financial account for a given user and type';
COMMENT ON FUNCTION public.register_restaurant_v2(uuid, text, text, text, text, double precision, double precision, text, jsonb)
  IS 'Atomic registration of restaurant: profile + restaurant + account, with logs';
