-- ============================================================================
-- REPARACIÓN URGENTE - RPC register_restaurant_atomic
-- ============================================================================
-- 🎯 OBJETIVO: Restaurar la función RPC correcta que espera la App Flutter.
-- 
-- 🔍 DIAGNÓSTICO:
--    La App envía 8 parámetros:
--      p_user_id, p_restaurant_name, p_phone, p_address, 
--      p_location_lat, p_location_lon, p_location_place_id, p_address_structured
--
--    El error indica que PostgREST no encuentra esta firma, pero sugiere una
--    con 10 parámetros (incluyendo email y name). Esto implica que la versión
--    en base de datos es incorrecta o no coincide.
--
-- 🛠️ SOLUCIÓN:
--    Este script elimina la versión de 8 parámetros (si existe) y la recrea
--    con la lógica correcta (incluyendo user_preferences).
-- ============================================================================

-- 1. Eliminar la función existente (versión de 8 parámetros)
DROP FUNCTION IF EXISTS public.register_restaurant_atomic(uuid, text, text, text, double precision, double precision, text, jsonb) CASCADE;

-- 2. Crear la función CORRECTA (8 parámetros)
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
  -- Validar que el usuario existe en public.users
  SELECT EXISTS(SELECT 1 FROM public.users WHERE id = p_user_id) INTO v_user_exists;
  
  IF NOT v_user_exists THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'User not found',
      'error_code', 'USER_NOT_FOUND',
      'data', NULL
    );
  END IF;

  -- Validar datos requeridos
  IF p_restaurant_name IS NULL OR trim(p_restaurant_name) = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Restaurant name is required',
      'error_code', 'INVALID_NAME',
      'data', NULL
    );
  END IF;

  -- Verificar que no exista otro restaurante con el mismo nombre
  IF EXISTS(SELECT 1 FROM public.restaurants WHERE name = p_restaurant_name) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Restaurant name already exists',
      'error_code', 'DUPLICATE_NAME',
      'data', NULL
    );
  END IF;

  -- Verificar que el usuario no tenga ya un restaurante
  IF EXISTS(SELECT 1 FROM public.restaurants WHERE user_id = p_user_id) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'User already has a restaurant',
      'error_code', 'DUPLICATE_RESTAURANT',
      'data', NULL
    );
  END IF;

  -- Insertar restaurante
  INSERT INTO public.restaurants (
    user_id,
    name,
    phone,
    address,
    location_lat,
    location_lon,
    location_place_id,
    address_structured,
    status,
    online,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_restaurant_name,
    COALESCE(p_phone, ''),
    COALESCE(p_address, ''),
    p_location_lat,
    p_location_lon,
    p_location_place_id,
    p_address_structured,
    'pending'::text,
    false,
    v_now,
    v_now
  )
  RETURNING id INTO v_restaurant_id;

  -- Asegurar cuenta financiera
  INSERT INTO public.accounts (
    user_id,
    account_type,
    balance,
    created_at,
    updated_at
  )
  VALUES (
    p_user_id,
    'restaurant'::text,
    0.00,
    v_now,
    v_now
  )
  ON CONFLICT (user_id) 
  DO UPDATE SET
    account_type = EXCLUDED.account_type,
    updated_at = v_now
  RETURNING id INTO v_account_id;

  -- Crear registro en user_preferences
  INSERT INTO public.user_preferences (
    user_id,
    restaurant_id,
    has_seen_onboarding,
    has_seen_restaurant_welcome,
    email_verified_congrats_shown,
    first_login_at,
    login_count,
    created_at,
    updated_at
  )
  VALUES (
    p_user_id,
    v_restaurant_id,
    false,
    false,
    false,
    NULL,
    0,
    v_now,
    v_now
  )
  ON CONFLICT (user_id) 
  DO UPDATE SET
    restaurant_id = EXCLUDED.restaurant_id,
    updated_at = v_now;

  -- Actualizar rol del usuario a 'restaurant'
  UPDATE public.users
  SET 
    role = 'restaurant'::text,
    updated_at = v_now
  WHERE id = p_user_id;

  -- Log de éxito
  BEGIN
    INSERT INTO public.debug_logs (scope, message, meta)
    VALUES (
      'register_restaurant_atomic',
      'Restaurant created successfully',
      jsonb_build_object(
        'user_id', p_user_id,
        'restaurant_id', v_restaurant_id,
        'account_id', v_account_id,
        'restaurant_name', p_restaurant_name
      )
    );
  EXCEPTION WHEN undefined_table THEN
    NULL;
  END;

  -- Notificar admin
  BEGIN
    INSERT INTO public.admin_notifications (
      category,
      entity_type,
      entity_id,
      title,
      message,
      metadata
    )
    VALUES (
      'registration'::text,
      'restaurant'::text,
      v_restaurant_id,
      'Nuevo restaurante registrado',
      format('El restaurante "%s" ha completado su registro y está pendiente de aprobación.', p_restaurant_name),
      jsonb_build_object(
        'restaurant_id', v_restaurant_id,
        'restaurant_name', p_restaurant_name,
        'user_id', p_user_id,
        'phone', p_phone
      )
    );
  EXCEPTION WHEN undefined_table THEN
    NULL;
  END;

  -- Retornar éxito
  RETURN jsonb_build_object(
    'success', true,
    'restaurant_id', v_restaurant_id,
    'account_id', v_account_id,
    'message', 'Restaurant registered successfully',
    'data', jsonb_build_object(
      'user_id', p_user_id,
      'restaurant_id', v_restaurant_id,
      'account_id', v_account_id
    )
  );

EXCEPTION WHEN OTHERS THEN
  -- Log del error
  BEGIN
    INSERT INTO public.debug_logs (scope, message, meta)
    VALUES (
      'register_restaurant_atomic',
      'ERROR: ' || SQLERRM,
      jsonb_build_object(
        'user_id', p_user_id,
        'restaurant_name', p_restaurant_name,
        'sqlstate', SQLSTATE,
        'error', SQLERRM
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'error_code', SQLSTATE,
    'data', NULL
  );
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.register_restaurant_atomic(uuid, text, text, text, double precision, double precision, text, jsonb) TO anon, authenticated, service_role;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
DO $$
BEGIN
  RAISE NOTICE '✅ Función register_restaurant_atomic (8 parámetros) recreada exitosamente.';
END $$;
