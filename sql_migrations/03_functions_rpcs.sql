-- ============================================================================
-- FUNCIONES Y RPCs (Remote Procedure Calls)
-- Procedimientos almacenados para operaciones complejas
-- ============================================================================

-- ============================================================================
-- FUNCIÓN: app_log
-- Registra logs de aplicación para debugging
-- ============================================================================
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

GRANT EXECUTE ON FUNCTION public.app_log(text, text, jsonb) TO anon, authenticated;

-- ============================================================================
-- FUNCIÓN: ensure_user_profile_v2
-- Crea o actualiza perfil de usuario
-- ============================================================================
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

  -- Upsert user profile
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

-- ============================================================================
-- FUNCIÓN: ensure_account_v2
-- Crea cuenta financiera si no existe
-- ============================================================================
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

-- ============================================================================
-- FUNCIÓN: register_restaurant_v2
-- Registro completo de restaurante (perfil + restaurante + cuenta)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.register_restaurant_v2(
  p_user_id            uuid,
  p_email              text,
  p_restaurant_name    text,
  p_phone              text DEFAULT '',
  p_address            text DEFAULT '',
  p_location_lat       double precision DEFAULT NULL,
  p_location_lon       double precision DEFAULT NULL,
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

  -- Ensure user profile with role = restaurant
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

  -- Ensure restaurant row exists
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

  -- Ensure financial account
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

-- ============================================================================
-- FUNCIÓN: register_delivery_agent_atomic
-- Registro completo de repartidor
-- ============================================================================
CREATE OR REPLACE FUNCTION public.register_delivery_agent_atomic(
  p_user_id uuid,
  p_email text,
  p_name text,
  p_phone text,
  p_vehicle_type text DEFAULT NULL,
  p_vehicle_plate text DEFAULT NULL,
  p_vehicle_model text DEFAULT NULL,
  p_vehicle_color text DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_result json;
  v_acc_result json;
  v_profile_id uuid;
BEGIN
  PERFORM public.app_log('register_delivery_agent_atomic', 'start', jsonb_build_object(
    'user_id', p_user_id,
    'email', p_email,
    'name', p_name
  ));

  -- Ensure user profile with role = delivery_agent
  v_user_result := public.ensure_user_profile_v2(
    p_user_id,
    p_email,
    'delivery_agent',
    p_name,
    p_phone
  );
  IF COALESCE((v_user_result->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'ensure_user_profile_v2 failed: %', v_user_result->>'error';
  END IF;

  -- Update vehicle info
  UPDATE public.users SET
    vehicle_type = p_vehicle_type,
    vehicle_plate = p_vehicle_plate,
    vehicle_model = p_vehicle_model,
    vehicle_color = p_vehicle_color,
    updated_at = now()
  WHERE id = p_user_id;

  -- Ensure delivery agent profile
  SELECT id INTO v_profile_id FROM public.delivery_agent_profiles WHERE user_id = p_user_id;
  IF v_profile_id IS NULL THEN
    INSERT INTO public.delivery_agent_profiles (
      id, user_id, status, account_state, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), p_user_id, 'offline', 'pending', now(), now()
    ) RETURNING id INTO v_profile_id;
  END IF;

  -- Ensure financial account
  v_acc_result := public.ensure_account_v2(p_user_id, 'delivery_agent');
  IF COALESCE((v_acc_result->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'ensure_account_v2 failed: %', v_acc_result->>'error';
  END IF;

  PERFORM public.app_log('register_delivery_agent_atomic', 'done', jsonb_build_object(
    'profile_id', v_profile_id,
    'account_id', v_acc_result->>'account_id'
  ));

  RETURN json_build_object(
    'success', true,
    'user_id', p_user_id,
    'profile_id', v_profile_id,
    'account_id', v_acc_result->>'account_id'
  );

EXCEPTION WHEN OTHERS THEN
  PERFORM public.app_log('register_delivery_agent_atomic', 'error', jsonb_build_object('err', SQLERRM));
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_delivery_agent_atomic(
  uuid, text, text, text, text, text, text, text
) TO anon, authenticated;

-- ============================================================================
-- FUNCIÓN: update_user_location
-- Actualiza ubicación de usuario (principalmente repartidores)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_user_location(
  p_user_id uuid,
  p_lat double precision,
  p_lon double precision,
  p_order_id uuid DEFAULT NULL,
  p_accuracy double precision DEFAULT NULL,
  p_speed double precision DEFAULT NULL,
  p_heading double precision DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Update or insert latest location
  INSERT INTO public.courier_locations_latest (
    user_id, order_id, lat, lon, accuracy, speed, heading, last_seen_at
  ) VALUES (
    p_user_id, p_order_id, p_lat, p_lon, p_accuracy, p_speed, p_heading, now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    order_id = EXCLUDED.order_id,
    lat = EXCLUDED.lat,
    lon = EXCLUDED.lon,
    accuracy = EXCLUDED.accuracy,
    speed = EXCLUDED.speed,
    heading = EXCLUDED.heading,
    last_seen_at = EXCLUDED.last_seen_at;

  -- Insert into history
  INSERT INTO public.courier_locations_history (
    user_id, order_id, lat, lon, accuracy, speed, heading, recorded_at
  ) VALUES (
    p_user_id, p_order_id, p_lat, p_lon, p_accuracy, p_speed, p_heading, now()
  );

  RETURN json_build_object('success', true);

EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_user_location(
  uuid, double precision, double precision, uuid, double precision, double precision, double precision
) TO authenticated;

-- ============================================================================
-- FUNCIÓN: update_client_default_address
-- Actualiza dirección por defecto del cliente
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_client_default_address(
  p_user_id uuid,
  p_address text,
  p_lat double precision,
  p_lon double precision,
  p_address_structured jsonb DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Update users table
  UPDATE public.users SET
    address = p_address,
    lat = p_lat,
    lon = p_lon,
    address_structured = p_address_structured,
    updated_at = now()
  WHERE id = p_user_id;

  -- Update or insert client profile
  INSERT INTO public.client_profiles (
    id, user_id, address, lat, lon, address_structured, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), p_user_id, p_address, p_lat, p_lon, p_address_structured, now(), now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    address = EXCLUDED.address,
    lat = EXCLUDED.lat,
    lon = EXCLUDED.lon,
    address_structured = EXCLUDED.address_structured,
    updated_at = EXCLUDED.updated_at;

  RETURN json_build_object('success', true);

EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_client_default_address(
  uuid, text, double precision, double precision, jsonb
) TO authenticated;

-- ============================================================================
-- FUNCIÓN: create_order_safe
-- Crea orden de forma segura
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_order_safe(
  p_user_id uuid,
  p_restaurant_id uuid,
  p_total_amount double precision,
  p_delivery_fee double precision DEFAULT 0.0,
  p_payment_method text DEFAULT 'cash',
  p_delivery_address text DEFAULT NULL,
  p_delivery_lat double precision DEFAULT NULL,
  p_delivery_lon double precision DEFAULT NULL,
  p_order_notes text DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id uuid;
  v_pickup_code text;
BEGIN
  -- Generate 4-digit pickup code
  v_pickup_code := LPAD(floor(random() * 10000)::text, 4, '0');

  INSERT INTO public.orders (
    id, user_id, restaurant_id, status, total_amount, delivery_fee,
    payment_method, delivery_address, delivery_lat, delivery_lon,
    pickup_code, order_notes, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), p_user_id, p_restaurant_id, 'pending', p_total_amount, p_delivery_fee,
    p_payment_method, p_delivery_address, p_delivery_lat, p_delivery_lon,
    v_pickup_code, p_order_notes, now(), now()
  ) RETURNING id INTO v_order_id;

  -- Insert initial status update
  INSERT INTO public.order_status_updates (
    id, order_id, status, updated_by, created_at
  ) VALUES (
    gen_random_uuid(), v_order_id, 'pending', p_user_id, now()
  );

  RETURN json_build_object(
    'success', true,
    'order_id', v_order_id,
    'pickup_code', v_pickup_code
  );

EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_order_safe(
  uuid, uuid, double precision, double precision, text, text, double precision, double precision, text
) TO authenticated;

-- ============================================================================
-- FUNCIÓN: insert_order_items_v2
-- Inserta items de orden de forma segura
-- ============================================================================
CREATE OR REPLACE FUNCTION public.insert_order_items_v2(
  p_order_id uuid,
  p_items jsonb
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item jsonb;
  v_count integer := 0;
BEGIN
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.order_items (
      id, order_id, product_id, quantity, price_at_time_of_order, created_at
    ) VALUES (
      gen_random_uuid(),
      p_order_id,
      (v_item->>'product_id')::uuid,
      (v_item->>'quantity')::integer,
      (v_item->>'price')::double precision,
      now()
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN json_build_object('success', true, 'items_inserted', v_count);

EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.insert_order_items_v2(uuid, jsonb) TO authenticated;

-- ============================================================================
-- FUNCIÓN: accept_order
-- Repartidor acepta una orden
-- ============================================================================
CREATE OR REPLACE FUNCTION public.accept_order(
  p_order_id uuid,
  p_delivery_agent_id uuid
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_confirm_code text;
BEGIN
  -- Generate 3-digit confirmation code
  v_confirm_code := LPAD(floor(random() * 1000)::text, 3, '0');

  -- Update order
  UPDATE public.orders SET
    delivery_agent_id = p_delivery_agent_id,
    status = 'assigned',
    assigned_at = now(),
    confirm_code = v_confirm_code,
    updated_at = now()
  WHERE id = p_order_id AND delivery_agent_id IS NULL;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Order already assigned or not found');
  END IF;

  -- Update delivery agent status
  UPDATE public.delivery_agent_profiles SET
    status = 'busy',
    updated_at = now()
  WHERE user_id = p_delivery_agent_id;

  -- Insert status update
  INSERT INTO public.order_status_updates (
    id, order_id, status, updated_by, created_at
  ) VALUES (
    gen_random_uuid(), p_order_id, 'assigned', p_delivery_agent_id, now()
  );

  RETURN json_build_object(
    'success', true,
    'confirm_code', v_confirm_code
  );

EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_order(uuid, uuid) TO authenticated;

-- ============================================================================
-- FUNCIÓN: upsert_combo_atomic
-- Crea o actualiza combo con sus items
-- ============================================================================
CREATE OR REPLACE FUNCTION public.upsert_combo_atomic(
  p_restaurant_id uuid,
  p_combo_name text,
  p_combo_price double precision,
  p_combo_description text DEFAULT NULL,
  p_combo_image_url text DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_product_id uuid;
  v_combo_id uuid;
  v_item jsonb;
BEGIN
  -- Create or update product
  INSERT INTO public.products (
    id, restaurant_id, name, description, price, image_url, type, is_available, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), p_restaurant_id, p_combo_name, p_combo_description, 
    p_combo_price, p_combo_image_url, 'combo', true, now(), now()
  ) RETURNING id INTO v_product_id;

  -- Create combo entry
  INSERT INTO public.product_combos (
    id, product_id, restaurant_id, created_at
  ) VALUES (
    gen_random_uuid(), v_product_id, p_restaurant_id, now()
  ) RETURNING id INTO v_combo_id;

  -- Insert combo items
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.product_combo_items (
      id, combo_id, product_id, quantity, created_at
    ) VALUES (
      gen_random_uuid(),
      v_combo_id,
      (v_item->>'product_id')::uuid,
      (v_item->>'quantity')::integer,
      now()
    );
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'product_id', v_product_id,
    'combo_id', v_combo_id
  );

EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_combo_atomic(
  uuid, text, double precision, text, text, jsonb
) TO authenticated;

-- ============================================================================
-- FUNCIÓN: update_my_phone_if_unique
-- Actualiza teléfono si es único
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_my_phone_if_unique(
  p_user_id uuid,
  p_phone text
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists boolean;
BEGIN
  -- Check if phone already exists for another user
  SELECT EXISTS (
    SELECT 1 FROM public.users 
    WHERE phone = p_phone AND id != p_user_id
  ) INTO v_exists;

  IF v_exists THEN
    RETURN json_build_object('success', false, 'error', 'Phone number already in use');
  END IF;

  -- Update phone
  UPDATE public.users SET
    phone = p_phone,
    updated_at = now()
  WHERE id = p_user_id;

  RETURN json_build_object('success', true);

EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_my_phone_if_unique(uuid, text) TO authenticated;

-- ============================================================================
-- FUNCIÓN: has_active_couriers
-- Verifica si hay repartidores activos disponibles
-- ============================================================================
CREATE OR REPLACE FUNCTION public.has_active_couriers()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM public.delivery_agent_profiles
  WHERE status = 'online' AND account_state = 'approved';
  
  RETURN v_count > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.has_active_couriers() TO authenticated, anon;
