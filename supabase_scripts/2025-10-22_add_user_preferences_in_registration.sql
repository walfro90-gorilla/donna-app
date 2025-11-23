-- =============================================================
-- Surgical update: ensure user_preferences is created during restaurant registration
-- Context: Auth user + users + restaurants + accounts are created correctly.
-- This patch adds an idempotent upsert into public.user_preferences, setting restaurant_id.
-- No changes to function signature or response shape.
-- =============================================================

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

  -- 4) ensure user_preferences row with restaurant_id (idempotent)
  --    Do not overwrite restaurant_id if it already exists; only set when NULL.
  INSERT INTO public.user_preferences (user_id, restaurant_id, created_at, updated_at)
  VALUES (p_user_id, v_restaurant_id, now(), now())
  ON CONFLICT (user_id) DO UPDATE
    SET restaurant_id = COALESCE(public.user_preferences.restaurant_id, EXCLUDED.restaurant_id),
        updated_at = now();

  -- 5) normalize role to restaurant if needed
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
