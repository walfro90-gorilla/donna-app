-- =============================================================
-- ATOMIC DELIVERY AGENT REGISTRATION RPC
-- =============================================================
-- Clean, professional RPC for delivery agent registration
-- Mirrors the successful register_restaurant_v2 pattern
-- Creates: users + delivery_agent_profiles + accounts + user_preferences
-- SECURITY DEFINER, idempotent, standard response shape {success, data, error}
-- =============================================================

-- Drop any existing versions to start fresh
DROP FUNCTION IF EXISTS public.register_delivery_agent_atomic CASCADE;
DROP FUNCTION IF EXISTS public.register_delivery_agent_v2 CASCADE;

-- Main atomic registration function
CREATE OR REPLACE FUNCTION public.register_delivery_agent_atomic(
  p_user_id uuid,
  p_email text,
  p_name text,
  p_phone text DEFAULT '',
  p_address text DEFAULT '',
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL,
  p_vehicle_type text DEFAULT 'motocicleta',
  p_vehicle_plate text DEFAULT '',
  p_vehicle_model text DEFAULT NULL,
  p_vehicle_color text DEFAULT NULL,
  p_emergency_contact_name text DEFAULT NULL,
  p_emergency_contact_phone text DEFAULT NULL,
  p_place_id text DEFAULT NULL,
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
  v_delivery_agent_id uuid;
  v_account_id uuid;
BEGIN
  -- 1) Delete any auto-created client_profiles (from auth trigger)
  -- This prevents role conflicts when auth.users trigger creates client profile first
  DELETE FROM public.client_profiles WHERE user_id = p_user_id;
  
  -- Also delete any client-type account created by trigger
  DELETE FROM public.accounts WHERE user_id = p_user_id AND account_type = 'client';

  -- 2) Create/update user profile with role='delivery_agent' FIRST (not 'client')
  INSERT INTO public.users (
    id, email, name, phone, address, role, 
    lat, lon, address_structured, email_confirm,
    created_at, updated_at
  ) VALUES (
    p_user_id,
    p_email,
    p_name,
    COALESCE(p_phone, ''),
    COALESCE(p_address, ''),
    'delivery_agent',
    p_lat,
    p_lon,
    p_address_structured,
    false,
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE
    SET email = COALESCE(NULLIF(EXCLUDED.email, ''), public.users.email),
        name = COALESCE(NULLIF(EXCLUDED.name, ''), public.users.name),
        phone = COALESCE(NULLIF(EXCLUDED.phone, ''), public.users.phone),
        address = COALESCE(NULLIF(EXCLUDED.address, ''), public.users.address),
        role = 'delivery_agent',  -- Force delivery_agent role
        lat = COALESCE(EXCLUDED.lat, public.users.lat),
        lon = COALESCE(EXCLUDED.lon, public.users.lon),
        address_structured = COALESCE(EXCLUDED.address_structured, public.users.address_structured),
        updated_at = now();

  -- 3) Create delivery_agent_profiles record (idempotent)
  INSERT INTO public.delivery_agent_profiles (
    user_id,
    profile_image_url,
    id_document_front_url,
    id_document_back_url,
    vehicle_type,
    vehicle_plate,
    vehicle_model,
    vehicle_color,
    vehicle_registration_url,
    vehicle_insurance_url,
    vehicle_photo_url,
    emergency_contact_name,
    emergency_contact_phone,
    status,
    account_state,
    onboarding_completed,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_profile_image_url,
    p_id_document_front_url,
    p_id_document_back_url,
    p_vehicle_type,
    p_vehicle_plate,
    p_vehicle_model,
    p_vehicle_color,
    p_vehicle_registration_url,
    p_vehicle_insurance_url,
    p_vehicle_photo_url,
    p_emergency_contact_name,
    p_emergency_contact_phone,
    'pending',
    'pending',
    false,
    now(),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE
    SET profile_image_url = COALESCE(EXCLUDED.profile_image_url, public.delivery_agent_profiles.profile_image_url),
        id_document_front_url = COALESCE(EXCLUDED.id_document_front_url, public.delivery_agent_profiles.id_document_front_url),
        id_document_back_url = COALESCE(EXCLUDED.id_document_back_url, public.delivery_agent_profiles.id_document_back_url),
        vehicle_type = COALESCE(EXCLUDED.vehicle_type, public.delivery_agent_profiles.vehicle_type),
        vehicle_plate = COALESCE(EXCLUDED.vehicle_plate, public.delivery_agent_profiles.vehicle_plate),
        vehicle_model = COALESCE(EXCLUDED.vehicle_model, public.delivery_agent_profiles.vehicle_model),
        vehicle_color = COALESCE(EXCLUDED.vehicle_color, public.delivery_agent_profiles.vehicle_color),
        vehicle_registration_url = COALESCE(EXCLUDED.vehicle_registration_url, public.delivery_agent_profiles.vehicle_registration_url),
        vehicle_insurance_url = COALESCE(EXCLUDED.vehicle_insurance_url, public.delivery_agent_profiles.vehicle_insurance_url),
        vehicle_photo_url = COALESCE(EXCLUDED.vehicle_photo_url, public.delivery_agent_profiles.vehicle_photo_url),
        emergency_contact_name = COALESCE(EXCLUDED.emergency_contact_name, public.delivery_agent_profiles.emergency_contact_name),
        emergency_contact_phone = COALESCE(EXCLUDED.emergency_contact_phone, public.delivery_agent_profiles.emergency_contact_phone),
        updated_at = now()
  RETURNING user_id INTO v_delivery_agent_id;

  -- 4) Ensure financial account for delivery_agent (idempotent)
  INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
  VALUES (p_user_id, 'delivery_agent', 0.0, now(), now())
  ON CONFLICT (user_id, account_type) DO UPDATE
    SET updated_at = EXCLUDED.updated_at
  RETURNING id INTO v_account_id;

  -- 5) Ensure user_preferences row (idempotent, no restaurant_id)
  INSERT INTO public.user_preferences (user_id, created_at, updated_at)
  VALUES (p_user_id, now(), now())
  ON CONFLICT (user_id) DO UPDATE
    SET updated_at = now();

  -- 6) Return success with IDs
  RETURN jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'user_id', p_user_id,
      'delivery_agent_id', v_delivery_agent_id,
      'account_id', v_account_id
    ),
    'error', NULL
  );

EXCEPTION WHEN OTHERS THEN
  -- Return error details
  RETURN jsonb_build_object(
    'success', false,
    'data', NULL,
    'error', SQLERRM
  );
END;
$$;

-- Grant execution permissions
GRANT EXECUTE ON FUNCTION public.register_delivery_agent_atomic(
  uuid, text, text, text, text, double precision, double precision, jsonb,
  text, text, text, text, text, text, text, text, text, text, text, text, text
) TO anon, authenticated, service_role;

-- Add helpful comment
COMMENT ON FUNCTION public.register_delivery_agent_atomic IS 
'Atomic registration for delivery agents. Creates user profile, delivery_agent_profiles, accounts, and user_preferences in a single transaction.';
