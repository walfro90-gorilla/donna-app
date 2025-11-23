DROP FUNCTION IF EXISTS public.upsert_delivery_agent_profile(
  uuid, text, text, text, text, text, text, text,
  double precision, double precision, jsonb,
  text, text, text, text, text, text
);

CREATE OR REPLACE FUNCTION public.upsert_delivery_agent_profile(
  p_user_id uuid,
  p_vehicle_type text,
  p_vehicle_plate text,
  p_vehicle_model text DEFAULT NULL,
  p_vehicle_color text DEFAULT NULL,
  p_emergency_contact_name text DEFAULT NULL,
  p_emergency_contact_phone text DEFAULT NULL,
  p_place_id text DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL,
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
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User ID does not exist in auth.users';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User profile does not exist. Create user profile first.';
  END IF;

  UPDATE public.users
  SET role = 'delivery_agent', updated_at = NOW()
  WHERE id = p_user_id AND COALESCE(role, '') <> 'delivery_agent';

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
    NOW(),
    NOW()
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
    updated_at = NOW();

  RETURN jsonb_build_object('success', true, 'user_id', p_user_id, 'message', 'Delivery agent profile upserted');
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_delivery_agent_profile(
  uuid, text, text, text, text, text, text, text, double precision, double precision, jsonb, text, text, text, text, text, text
) TO anon;

GRANT EXECUTE ON FUNCTION public.upsert_delivery_agent_profile(
  uuid, text, text, text, text, text, text, text, double precision, double precision, jsonb, text, text, text, text, text, text
) TO authenticated;
