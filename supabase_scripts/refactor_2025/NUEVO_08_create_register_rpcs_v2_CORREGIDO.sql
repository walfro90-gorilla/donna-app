-- =====================================================================
-- 08_create_register_rpcs_v2_CORREGIDO.sql
-- =====================================================================
-- Crea RPCs para registro de perfiles basados en DATABASE_SCHEMA.sql real
-- 
-- TABLAS REALES (según DATABASE_SCHEMA.sql):
--   • public.users (id, email, name, phone, role, created_at, updated_at, email_confirm)
--   • public.client_profiles (user_id, address, lat, lon, address_structured, ...)
--   • public.restaurants (id, user_id, name, description, logo_url, status, address, phone, ...)
--   • public.delivery_agent_profiles (user_id, vehicle_type, vehicle_plate, status, account_state, ...)
--
-- ROLES EN users.role:
--   • 'cliente'
--   • 'restaurante'
--   • 'repartidor'
--   • 'admin'
--
-- =====================================================================

-- ====================================
-- LIMPIEZA: Eliminar funciones anteriores
-- ====================================
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN (
    SELECT p.oid,
           n.nspname AS schema_name,
           p.proname AS fn_name,
           pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('register_client','register_restaurant','register_delivery_agent')
  ) LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s) CASCADE;', r.schema_name, r.fn_name, r.args);
    RAISE NOTICE 'Eliminada: %.%(%)', r.schema_name, r.fn_name, r.args;
  END LOOP;
END$$;

-- ====================================
-- 1️⃣ register_client
-- ====================================
-- Crea usuario + perfil de cliente
-- Parámetros: email, password, name, phone, address, lat, lon, address_structured
-- ====================================
CREATE OR REPLACE FUNCTION public.register_client(
  p_email             text,
  p_password          text,
  p_name              text DEFAULT NULL,
  p_phone             text DEFAULT NULL,
  p_address           text DEFAULT NULL,
  p_lat               double precision DEFAULT NULL,
  p_lon               double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
  v_result jsonb;
BEGIN
  -- 1) Crear usuario en auth.users (Supabase maneja esto automáticamente con signUp)
  -- Para este RPC, asumimos que el usuario YA está creado en auth.users
  -- y simplemente tomamos auth.uid()
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado. Debes llamar a auth.signUp primero.';
  END IF;

  -- 2) Insertar en public.users
  INSERT INTO public.users (
    id, 
    email, 
    name, 
    phone, 
    role,
    email_confirm,
    created_at,
    updated_at
  ) VALUES (
    v_user_id,
    COALESCE(p_email, ''),
    p_name,
    p_phone,
    'cliente',
    false,
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE
  SET 
    email = COALESCE(EXCLUDED.email, public.users.email),
    name = COALESCE(EXCLUDED.name, public.users.name),
    phone = COALESCE(EXCLUDED.phone, public.users.phone),
    role = 'cliente',
    updated_at = now();

  -- 3) Insertar en client_profiles
  INSERT INTO public.client_profiles (
    user_id,
    address,
    lat,
    lon,
    address_structured,
    created_at,
    updated_at
  ) VALUES (
    v_user_id,
    p_address,
    p_lat,
    p_lon,
    p_address_structured,
    now(),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE
  SET
    address = COALESCE(EXCLUDED.address, public.client_profiles.address),
    lat = COALESCE(EXCLUDED.lat, public.client_profiles.lat),
    lon = COALESCE(EXCLUDED.lon, public.client_profiles.lon),
    address_structured = COALESCE(EXCLUDED.address_structured, public.client_profiles.address_structured),
    updated_at = now();

  -- 4) Crear preferencias de usuario
  INSERT INTO public.user_preferences (user_id, created_at, updated_at)
  VALUES (v_user_id, now(), now())
  ON CONFLICT (user_id) DO NOTHING;

  -- 5) Retornar resultado
  v_result := jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'role', 'cliente',
    'message', 'Cliente registrado exitosamente'
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_client(text, text, text, text, text, double precision, double precision, jsonb) TO authenticated, anon;

COMMENT ON FUNCTION public.register_client IS 'Registra un nuevo cliente en public.users y client_profiles';

-- ====================================
-- 2️⃣ register_restaurant
-- ====================================
-- Crea usuario + perfil de restaurante
-- Parámetros: email, password, restaurant_name, contact_name, phone, address, lat, lon, address_structured
-- ====================================
CREATE OR REPLACE FUNCTION public.register_restaurant(
  p_email              text,
  p_password           text,
  p_restaurant_name    text,
  p_contact_name       text DEFAULT NULL,
  p_phone              text DEFAULT NULL,
  p_address            text DEFAULT NULL,
  p_location_lat       double precision DEFAULT NULL,
  p_location_lon       double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
  v_restaurant_id uuid;
  v_result jsonb;
BEGIN
  -- 1) Obtener user_id de auth
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado. Debes llamar a auth.signUp primero.';
  END IF;

  -- 2) Insertar en public.users
  INSERT INTO public.users (
    id, 
    email, 
    name, 
    phone, 
    role,
    email_confirm,
    created_at,
    updated_at
  ) VALUES (
    v_user_id,
    COALESCE(p_email, ''),
    p_contact_name,
    p_phone,
    'restaurante',
    false,
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE
  SET 
    email = COALESCE(EXCLUDED.email, public.users.email),
    name = COALESCE(EXCLUDED.name, public.users.name),
    phone = COALESCE(EXCLUDED.phone, public.users.phone),
    role = 'restaurante',
    updated_at = now();

  -- 3) Insertar en restaurants
  INSERT INTO public.restaurants (
    id,
    user_id,
    name,
    description,
    address,
    phone,
    location_lat,
    location_lon,
    address_structured,
    status,
    online,
    onboarding_completed,
    onboarding_step,
    profile_completion_percentage,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_user_id,
    p_restaurant_name,
    '',
    p_address,
    p_phone,
    p_location_lat,
    p_location_lon,
    p_address_structured,
    'pending',
    false,
    false,
    0,
    0,
    now(),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE
  SET
    name = COALESCE(EXCLUDED.name, public.restaurants.name),
    address = COALESCE(EXCLUDED.address, public.restaurants.address),
    phone = COALESCE(EXCLUDED.phone, public.restaurants.phone),
    location_lat = COALESCE(EXCLUDED.location_lat, public.restaurants.location_lat),
    location_lon = COALESCE(EXCLUDED.location_lon, public.restaurants.location_lon),
    address_structured = COALESCE(EXCLUDED.address_structured, public.restaurants.address_structured),
    updated_at = now()
  RETURNING id INTO v_restaurant_id;

  -- 4) Crear preferencias de usuario
  INSERT INTO public.user_preferences (user_id, restaurant_id, created_at, updated_at)
  VALUES (v_user_id, v_restaurant_id, now(), now())
  ON CONFLICT (user_id) DO UPDATE
  SET restaurant_id = v_restaurant_id;

  -- 5) Crear cuenta financiera del restaurante
  INSERT INTO public.accounts (id, user_id, account_type, balance, created_at, updated_at)
  VALUES (gen_random_uuid(), v_user_id, 'restaurant', 0.00, now(), now())
  ON CONFLICT DO NOTHING;

  -- 6) Crear notificación para admins
  INSERT INTO public.admin_notifications (
    target_role,
    category,
    entity_type,
    entity_id,
    title,
    message,
    metadata,
    created_at
  ) VALUES (
    'admin',
    'registration',
    'restaurant',
    v_user_id,
    'Nuevo restaurante registrado',
    'El restaurante "' || p_restaurant_name || '" ha solicitado registro.',
    jsonb_build_object(
      'restaurant_name', p_restaurant_name,
      'contact_name', p_contact_name,
      'phone', p_phone,
      'email', p_email
    ),
    now()
  );

  -- 7) Retornar resultado
  v_result := jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'restaurant_id', v_restaurant_id,
    'role', 'restaurante',
    'message', 'Restaurante registrado exitosamente. Pendiente de aprobación.'
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_restaurant(text, text, text, text, text, text, double precision, double precision, jsonb) TO authenticated, anon;

COMMENT ON FUNCTION public.register_restaurant IS 'Registra un nuevo restaurante en public.users y restaurants';

-- ====================================
-- 3️⃣ register_delivery_agent
-- ====================================
-- Crea usuario + perfil de repartidor
-- Parámetros: email, password, name, phone, vehicle_type
-- ====================================
CREATE OR REPLACE FUNCTION public.register_delivery_agent(
  p_email        text,
  p_password     text,
  p_name         text,
  p_phone        text DEFAULT NULL,
  p_vehicle_type text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
  v_result jsonb;
BEGIN
  -- 1) Obtener user_id de auth
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado. Debes llamar a auth.signUp primero.';
  END IF;

  -- 2) Insertar en public.users
  INSERT INTO public.users (
    id, 
    email, 
    name, 
    phone, 
    role,
    email_confirm,
    created_at,
    updated_at
  ) VALUES (
    v_user_id,
    COALESCE(p_email, ''),
    p_name,
    p_phone,
    'repartidor',
    false,
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE
  SET 
    email = COALESCE(EXCLUDED.email, public.users.email),
    name = COALESCE(EXCLUDED.name, public.users.name),
    phone = COALESCE(EXCLUDED.phone, public.users.phone),
    role = 'repartidor',
    updated_at = now();

  -- 3) Insertar en delivery_agent_profiles
  INSERT INTO public.delivery_agent_profiles (
    user_id,
    vehicle_type,
    status,
    account_state,
    onboarding_completed,
    created_at,
    updated_at
  ) VALUES (
    v_user_id,
    p_vehicle_type,
    'pending',
    'pending',
    false,
    now(),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE
  SET
    vehicle_type = COALESCE(EXCLUDED.vehicle_type, public.delivery_agent_profiles.vehicle_type),
    updated_at = now();

  -- 4) Crear preferencias de usuario
  INSERT INTO public.user_preferences (user_id, created_at, updated_at)
  VALUES (v_user_id, now(), now())
  ON CONFLICT (user_id) DO NOTHING;

  -- 5) Crear cuenta financiera del repartidor
  INSERT INTO public.accounts (id, user_id, account_type, balance, created_at, updated_at)
  VALUES (gen_random_uuid(), v_user_id, 'delivery_agent', 0.00, now(), now())
  ON CONFLICT DO NOTHING;

  -- 6) Crear notificación para admins
  INSERT INTO public.admin_notifications (
    target_role,
    category,
    entity_type,
    entity_id,
    title,
    message,
    metadata,
    created_at
  ) VALUES (
    'admin',
    'registration',
    'delivery_agent',
    v_user_id,
    'Nuevo repartidor registrado',
    'El repartidor "' || p_name || '" ha solicitado registro.',
    jsonb_build_object(
      'name', p_name,
      'phone', p_phone,
      'email', p_email,
      'vehicle_type', p_vehicle_type
    ),
    now()
  );

  -- 7) Retornar resultado
  v_result := jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'role', 'repartidor',
    'message', 'Repartidor registrado exitosamente. Pendiente de aprobación.'
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_delivery_agent(text, text, text, text, text) TO authenticated, anon;

COMMENT ON FUNCTION public.register_delivery_agent IS 'Registra un nuevo repartidor en public.users y delivery_agent_profiles';

-- ====================================
-- ✅ VERIFICACIÓN FINAL
-- ====================================
SELECT 
  '✅ FUNCIONES CREADAS EXITOSAMENTE' as status,
  COUNT(*) as total_funciones
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('register_client', 'register_restaurant', 'register_delivery_agent');
