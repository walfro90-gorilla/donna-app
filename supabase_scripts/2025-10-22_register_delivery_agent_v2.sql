-- =============================================================
-- New RPC: register_delivery_agent_v2 (atomic, SECURITY DEFINER)
-- Purpose: Full registration flow for delivery agents mirroring register_restaurant_v2
-- Behavior:
--   1) ensure_user_profile_public (role = 'delivery_agent')
--   2) upsert into delivery_agent_profiles with provided fields
--   3) upsert financial account (accounts) with type 'delivery_agent'
--   4) ensure user_preferences row exists (idempotent)
--   5) normalize users.role to 'delivery_agent' if still empty/client variants
-- Response: { success, data: { user_id, delivery_profile_user_id, account_id }, error }
-- =============================================================

CREATE OR REPLACE FUNCTION public.register_delivery_agent_v2(
  p_user_id uuid,
  p_email text,
  p_name text,
  p_phone text DEFAULT '',
  p_address text DEFAULT '',
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL,
  -- vehicle and profile data
  p_vehicle_type text,
  p_vehicle_plate text,
  p_vehicle_model text DEFAULT NULL,
  p_vehicle_color text DEFAULT NULL,
  p_emergency_contact_name text DEFAULT NULL,
  p_emergency_contact_phone text DEFAULT NULL,
  p_place_id text DEFAULT NULL,
  -- documents/images
  p_profile_image_url text DEFAULT NULL,
  p_id_document_front_url text DEFAULT NULL,
  p_id_document_back_url text DEFAULT NULL,
  p_vehicle_photo_url text DEFAULT NULL,
  p_vehicle_registration_url text DEFAULT NULL,
  p_vehicle_insurance_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_id uuid;
  v_now timestamptz := now();
  v_role text;
BEGIN
  -- 0) Validate auth user exists
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User ID does not exist in auth.users';
  END IF;

  -- 1) Ensure public user profile (role delivery_agent)
  PERFORM public.ensure_user_profile_public(
    p_user_id => p_user_id,
    p_email => p_email,
    p_name => COALESCE(p_name, ''),
    p_role => 'delivery_agent',
    p_phone => p_phone,
    p_address => p_address,
    p_lat => p_lat,
    p_lon => p_lon,
    p_address_structured => p_address_structured
  );

  -- 2) Upsert delivery_agent_profiles (by user_id)
  INSERT INTO public.delivery_agent_profiles (
    user_id,
    vehicle_type,
    vehicle_plate,
    vehicle_model,
    vehicle_color,
    emergency_contact_name,
    emergency_contact_phone,
    place_id,
    lat,
    lon,
    address_structured,
    profile_image_url,
    id_document_front_url,
    id_document_back_url,
    vehicle_photo_url,
    vehicle_registration_url,
    vehicle_insurance_url,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_vehicle_type,
    p_vehicle_plate,
    p_vehicle_model,
    p_vehicle_color,
    p_emergency_contact_name,
    p_emergency_contact_phone,
    p_place_id,
    p_lat,
    p_lon,
    p_address_structured,
    p_profile_image_url,
    p_id_document_front_url,
    p_id_document_back_url,
    p_vehicle_photo_url,
    p_vehicle_registration_url,
    p_vehicle_insurance_url,
    v_now,
    v_now
  )
  ON CONFLICT (user_id) DO UPDATE SET
    vehicle_type = COALESCE(EXCLUDED.vehicle_type, delivery_agent_profiles.vehicle_type),
    vehicle_plate = COALESCE(EXCLUDED.vehicle_plate, delivery_agent_profiles.vehicle_plate),
    vehicle_model = COALESCE(EXCLUDED.vehicle_model, delivery_agent_profiles.vehicle_model),
    vehicle_color = COALESCE(EXCLUDED.vehicle_color, delivery_agent_profiles.vehicle_color),
    emergency_contact_name = COALESCE(EXCLUDED.emergency_contact_name, delivery_agent_profiles.emergency_contact_name),
    emergency_contact_phone = COALESCE(EXCLUDED.emergency_contact_phone, delivery_agent_profiles.emergency_contact_phone),
    place_id = COALESCE(EXCLUDED.place_id, delivery_agent_profiles.place_id),
    lat = COALESCE(EXCLUDED.lat, delivery_agent_profiles.lat),
    lon = COALESCE(EXCLUDED.lon, delivery_agent_profiles.lon),
    address_structured = COALESCE(EXCLUDED.address_structured, delivery_agent_profiles.address_structured),
    profile_image_url = COALESCE(EXCLUDED.profile_image_url, delivery_agent_profiles.profile_image_url),
    id_document_front_url = COALESCE(EXCLUDED.id_document_front_url, delivery_agent_profiles.id_document_front_url),
    id_document_back_url = COALESCE(EXCLUDED.id_document_back_url, delivery_agent_profiles.id_document_back_url),
    vehicle_photo_url = COALESCE(EXCLUDED.vehicle_photo_url, delivery_agent_profiles.vehicle_photo_url),
    vehicle_registration_url = COALESCE(EXCLUDED.vehicle_registration_url, delivery_agent_profiles.vehicle_registration_url),
    vehicle_insurance_url = COALESCE(EXCLUDED.vehicle_insurance_url, delivery_agent_profiles.vehicle_insurance_url),
    updated_at = v_now;

  -- 3) Ensure financial account (user_id + account_type)
  INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
  VALUES (p_user_id, 'delivery_agent', 0.0, v_now, v_now)
  ON CONFLICT (user_id, account_type) DO UPDATE
    SET updated_at = EXCLUDED.updated_at
  RETURNING id INTO v_account_id;

  -- 4) Ensure user_preferences row exists (idempotent)
  BEGIN
    INSERT INTO public.user_preferences (user_id, created_at, updated_at)
    VALUES (p_user_id, v_now, v_now)
    ON CONFLICT (user_id) DO UPDATE
      SET updated_at = v_now;
  EXCEPTION WHEN undefined_table THEN
    -- If user_preferences table is missing in this environment, do not fail the whole function
    RAISE NOTICE 'user_preferences table not found; skipping preferences creation';
  WHEN others THEN
    -- Never block registration due to preferences; just log
    RAISE NOTICE 'user_preferences upsert skipped due to: %', SQLERRM;
  END;

  -- 5) Normalize role to delivery_agent if still empty/client variants
  SELECT role INTO v_role FROM public.users WHERE id = p_user_id;
  IF COALESCE(v_role,'') IN ('', 'client', 'cliente') THEN
    UPDATE public.users SET role = 'delivery_agent', updated_at = v_now WHERE id = p_user_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'user_id', p_user_id,
      'delivery_profile_user_id', p_user_id,
      'account_id', v_account_id
    ),
    'error', NULL
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_delivery_agent_v2(
  uuid, text, text, text, text, double precision, double precision, jsonb,
  text, text, text, text, text, text, text, text, text, text, text, text, text
) TO anon, authenticated, service_role;
