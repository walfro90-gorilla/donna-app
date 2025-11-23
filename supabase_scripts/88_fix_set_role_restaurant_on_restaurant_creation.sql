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

  UPDATE public.users
  SET role = 'restaurant', updated_at = NOW()
  WHERE id = p_user_id AND COALESCE(role, '') <> 'restaurant';

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
