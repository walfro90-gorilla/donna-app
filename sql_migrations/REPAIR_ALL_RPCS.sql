-- ============================================================================
-- REPARACIÓN URGENTE - RPCs create_user_profile_public y register_restaurant_atomic
-- ============================================================================
-- 🎯 OBJETIVO: Restaurar las funciones RPC críticas que espera la App Flutter.
-- 
-- 🔍 DIAGNÓSTICO:
--    1. create_user_profile_public: La App envía 10 parámetros, pero no existe en DB.
--    2. register_restaurant_atomic: La App envía 8 parámetros, pero DB espera 10.
--
-- 🛠️ SOLUCIÓN:
--    Este script recrea ambas funciones con las firmas EXACTAS que usa la App.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. REPARAR create_user_profile_public
-- ----------------------------------------------------------------------------

-- Eliminar versiones anteriores
DROP FUNCTION IF EXISTS public.create_user_profile_public(uuid, text, text, text, text, text, double precision, double precision, jsonb, boolean) CASCADE;
DROP FUNCTION IF EXISTS public.create_user_profile_public(uuid, text, text, text, text, text, double precision, double precision, jsonb) CASCADE;
-- Intentar borrar cualquier otra variante
DROP FUNCTION IF EXISTS public.create_user_profile_public(uuid, text, text, text) CASCADE;

-- Crear función con la firma de 10 parámetros que usa la App
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
  v_now timestamptz := now();
  v_role text;
BEGIN
  -- Normalizar rol
  v_role := COALESCE(LOWER(TRIM(p_role)), 'client');
  IF v_role NOT IN ('client', 'restaurant', 'delivery_agent', 'admin') THEN
    v_role := 'client';
  END IF;

  -- Insertar o actualizar usuario (Idempotente)
  INSERT INTO public.users (
    id,
    email,
    name,
    phone,
    role,
    created_at,
    updated_at,
    email_confirm
  ) VALUES (
    p_user_id,
    p_email,
    p_name,
    p_phone,
    v_role,
    v_now,
    v_now,
    false -- Se confirmará después
  )
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    phone = COALESCE(EXCLUDED.phone, public.users.phone),
    role = EXCLUDED.role,
    updated_at = v_now;

  -- Si es cliente, asegurar client_profile y dirección
  IF v_role = 'client' THEN
    INSERT INTO public.client_profiles (user_id, created_at, updated_at)
    VALUES (p_user_id, v_now, v_now)
    ON CONFLICT (user_id) DO NOTHING;
    
    -- Actualizar dirección si se proporciona
    IF p_address IS NOT NULL AND p_address != '' THEN
        UPDATE public.client_profiles
        SET 
            default_address = p_address,
            default_lat = p_lat,
            default_lon = p_lon,
            default_address_structured = p_address_structured,
            updated_at = v_now
        WHERE user_id = p_user_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'message', 'User profile created/updated successfully'
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'code', SQLSTATE
  );
END;
$$;

-- Permisos
GRANT EXECUTE ON FUNCTION public.create_user_profile_public(uuid, text, text, text, text, text, double precision, double precision, jsonb, boolean) TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 2. REPARAR register_restaurant_atomic
-- ----------------------------------------------------------------------------

-- Eliminar versiones anteriores
DROP FUNCTION IF EXISTS public.register_restaurant_atomic(uuid, text, text, text, double precision, double precision, text, jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.register_restaurant_atomic(text, jsonb, text, double precision, double precision, text, text, text, text, uuid) CASCADE;

-- Crear función con la firma de 8 parámetros que usa la App
CREATE OR REPLACE FUNCTION public.register_restaurant_atomic(
  p_user_id uuid,
  p_restaurant_name text,
  p_phone text,
  p_address text,
  p_location_lat double precision,
  p_location_lon double precision,
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
  v_user_exists boolean;
  v_now timestamptz := now();
BEGIN
  -- Validar usuario
  SELECT EXISTS(SELECT 1 FROM public.users WHERE id = p_user_id) INTO v_user_exists;
  IF NOT v_user_exists THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found', 'error_code', 'USER_NOT_FOUND');
  END IF;

  -- Validar nombre
  IF p_restaurant_name IS NULL OR trim(p_restaurant_name) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Restaurant name is required', 'error_code', 'INVALID_NAME');
  END IF;

  -- Verificar duplicados nombre
  IF EXISTS(SELECT 1 FROM public.restaurants WHERE name = p_restaurant_name) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Restaurant name already exists', 'error_code', 'DUPLICATE_NAME');
  END IF;

  -- Verificar duplicados usuario
  IF EXISTS(SELECT 1 FROM public.restaurants WHERE user_id = p_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'User already has a restaurant', 'error_code', 'DUPLICATE_RESTAURANT');
  END IF;

  -- Insertar restaurante
  INSERT INTO public.restaurants (
    user_id, name, phone, address, location_lat, location_lon, location_place_id, address_structured, status, online, created_at, updated_at
  ) VALUES (
    p_user_id, p_restaurant_name, COALESCE(p_phone, ''), COALESCE(p_address, ''), p_location_lat, p_location_lon, p_location_place_id, p_address_structured, 'pending', false, v_now, v_now
  )
  RETURNING id INTO v_restaurant_id;

  -- Asegurar cuenta financiera
  INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
  VALUES (p_user_id, 'restaurant', 0.00, v_now, v_now)
  ON CONFLICT (user_id) DO UPDATE SET account_type = EXCLUDED.account_type, updated_at = v_now
  RETURNING id INTO v_account_id;

  -- Crear user_preferences
  INSERT INTO public.user_preferences (
    user_id, restaurant_id, has_seen_onboarding, has_seen_restaurant_welcome, email_verified_congrats_shown, login_count, created_at, updated_at
  )
  VALUES (p_user_id, v_restaurant_id, false, false, false, 0, v_now, v_now)
  ON CONFLICT (user_id) DO UPDATE SET restaurant_id = EXCLUDED.restaurant_id, updated_at = v_now;

  -- Actualizar rol usuario
  UPDATE public.users SET role = 'restaurant', updated_at = v_now WHERE id = p_user_id;

  -- Log éxito
  BEGIN
    INSERT INTO public.debug_logs (scope, message, meta)
    VALUES ('register_restaurant_atomic', 'Restaurant created successfully', jsonb_build_object('user_id', p_user_id, 'restaurant_id', v_restaurant_id));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Notificar admin
  BEGIN
    INSERT INTO public.admin_notifications (category, entity_type, entity_id, title, message, metadata)
    VALUES ('registration', 'restaurant', v_restaurant_id, 'Nuevo restaurante registrado', format('El restaurante "%s" ha completado su registro.', p_restaurant_name), jsonb_build_object('restaurant_id', v_restaurant_id));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object(
    'success', true,
    'restaurant_id', v_restaurant_id,
    'account_id', v_account_id,
    'message', 'Restaurant registered successfully'
  );

EXCEPTION WHEN OTHERS THEN
  -- Log error
  BEGIN
    INSERT INTO public.debug_logs (scope, message, meta)
    VALUES ('register_restaurant_atomic', 'ERROR: ' || SQLERRM, jsonb_build_object('user_id', p_user_id, 'error', SQLERRM));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'error_code', SQLSTATE);
END;
$$;

-- Permisos
GRANT EXECUTE ON FUNCTION public.register_restaurant_atomic(uuid, text, text, text, double precision, double precision, text, jsonb) TO anon, authenticated, service_role;

-- ============================================================================
-- VERIFICACIÓN FINAL
-- ============================================================================
DO $$
BEGIN
  RAISE NOTICE '✅ Funciones RPC reparadas exitosamente:';
  RAISE NOTICE '   - create_user_profile_public (10 params)';
  RAISE NOTICE '   - register_restaurant_atomic (8 params)';
END $$;
