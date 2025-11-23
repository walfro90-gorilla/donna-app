-- ============================================================================
-- 01_CREATE_REGISTRATION_RPCS.SQL
-- ============================================================================
-- Creates registration RPCs ONLY for delivery agents and restaurants
-- CLIENT REGISTRATION IS NOT TOUCHED (already working correctly)
-- ============================================================================

-- ============================================================================
-- 1. DROP EXISTING FUNCTIONS (Clean slate)
-- ============================================================================

DROP FUNCTION IF EXISTS public.register_delivery_agent_v2(text, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.register_restaurant_v2(text, text, text, text, text, double precision, double precision, jsonb);

-- ============================================================================
-- 2. CREATE DELIVERY AGENT REGISTRATION RPC
-- ============================================================================

CREATE OR REPLACE FUNCTION public.register_delivery_agent_v2(
  p_email text,
  p_password text,
  p_phone text,
  p_full_name text,
  p_vehicle_type text DEFAULT NULL,
  p_license_plate text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
  v_raw_meta jsonb;
BEGIN
  -- Build metadata with English role
  v_raw_meta := jsonb_build_object(
    'user_role', 'delivery_agent',
    'full_name', p_full_name,
    'phone', p_phone,
    'vehicle_type', COALESCE(p_vehicle_type, ''),
    'license_plate', COALESCE(p_license_plate, '')
  );

  -- Create auth user
  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  )
  VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(),
    'authenticated',
    'authenticated',
    p_email,
    crypt(p_password, gen_salt('bf')),
    NULL,
    '{"provider":"email","providers":["email"]}'::jsonb,
    v_raw_meta,
    now(),
    now(),
    encode(gen_random_bytes(32), 'hex'),
    '',
    '',
    ''
  )
  RETURNING id INTO v_user_id;

  -- The trigger master_handle_signup will create the profile automatically

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'message', 'Delivery agent registered successfully. Please verify your email.'
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

COMMENT ON FUNCTION public.register_delivery_agent_v2 IS 
'Registers a new delivery agent with role delivery_agent';

-- ============================================================================
-- 3. CREATE RESTAURANT REGISTRATION RPC
-- ============================================================================

CREATE OR REPLACE FUNCTION public.register_restaurant_v2(
  p_email text,
  p_password text,
  p_phone text,
  p_restaurant_name text,
  p_restaurant_address text DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
  v_raw_meta jsonb;
BEGIN
  -- Build metadata with English role
  v_raw_meta := jsonb_build_object(
    'user_role', 'restaurant',
    'phone', p_phone,
    'restaurant_name', p_restaurant_name,
    'restaurant_address', COALESCE(p_restaurant_address, ''),
    'lat', p_lat,
    'lon', p_lon,
    'address_structured', COALESCE(p_address_structured, '{}'::jsonb)
  );

  -- Create auth user
  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  )
  VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(),
    'authenticated',
    'authenticated',
    p_email,
    crypt(p_password, gen_salt('bf')),
    NULL,
    '{"provider":"email","providers":["email"]}'::jsonb,
    v_raw_meta,
    now(),
    now(),
    encode(gen_random_bytes(32), 'hex'),
    '',
    '',
    ''
  )
  RETURNING id INTO v_user_id;

  -- The trigger master_handle_signup will create the profile automatically

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'message', 'Restaurant registered successfully. Please verify your email.'
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

COMMENT ON FUNCTION public.register_restaurant_v2 IS 
'Registers a new restaurant with role restaurant';

-- ============================================================================
-- 4. GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.register_delivery_agent_v2 TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_restaurant_v2 TO anon, authenticated;

-- ============================================================================
-- SUCCESS MESSAGE
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ Step 1 Complete: Registration RPCs';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ register_delivery_agent_v2() created (role: delivery_agent)';
  RAISE NOTICE '✅ register_restaurant_v2() created (role: restaurant)';
  RAISE NOTICE '⚠️  CLIENT registration NOT MODIFIED (already working)';
END $$;
