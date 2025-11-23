-- ============================================================================
-- FIX QUIRÚRGICO - Agregar user_preferences al registro de restaurantes
-- ============================================================================
-- 🎯 OBJETIVO: Agregar la creación de user_preferences en el RPC atómico
-- 
-- ⚠️  IMPORTANTE: Este script solo MODIFICA el RPC register_restaurant_atomic()
--    sin tocar nada más que ya funciona correctamente.
-- 
-- ✅ Safe to run: Solo actualiza la función RPC
-- ⏱️ Tiempo de ejecución: < 5 segundos
-- ============================================================================

-- Drop existing function to replace it
DROP FUNCTION IF EXISTS public.register_restaurant_atomic(uuid, text, text, text, double precision, double precision, text, jsonb) CASCADE;

-- Recrear RPC con user_preferences incluido
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

  -- Insertar restaurante (siguiendo el schema exacto de DATABASE_SCHEMA.sql)
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

  -- Asegurar cuenta financiera (idempotente, siguiendo patrón del schema)
  -- accounts.user_id tiene UNIQUE constraint, así que ON CONFLICT funciona
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

  -- 🆕 AGREGAR: Crear registro en user_preferences (idempotente)
  -- user_preferences.user_id tiene UNIQUE constraint
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

  -- Log de éxito (si la tabla debug_logs existe)
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
    -- Si la tabla no existe, simplemente ignorar el log
    NULL;
  END;

  -- Notificar admin (si la tabla admin_notifications existe)
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
    -- Si la tabla no existe, simplemente ignorar la notificación
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

-- Grant execute permissions (siguiendo patrón del schema)
GRANT EXECUTE ON FUNCTION public.register_restaurant_atomic(uuid, text, text, text, double precision, double precision, text, jsonb) TO anon, authenticated, service_role;

-- ============================================================================
-- VERIFICACIÓN FINAL
-- ============================================================================

DO $$
DECLARE
  v_rpc_exists boolean;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ FIX APLICADO EXITOSAMENTE';
  RAISE NOTICE '========================================';
  
  -- Check if RPC exists
  SELECT EXISTS(
    SELECT 1 FROM pg_proc 
    WHERE proname = 'register_restaurant_atomic'
      AND pronamespace = 'public'::regnamespace
  ) INTO v_rpc_exists;
  
  IF v_rpc_exists THEN
    RAISE NOTICE '✅ RPC register_restaurant_atomic actualizada';
    RAISE NOTICE '';
    RAISE NOTICE '🆕 CAMBIOS APLICADOS:';
    RAISE NOTICE '   • Ahora crea registro en user_preferences';
    RAISE NOTICE '   • Vincula restaurant_id en user_preferences';
    RAISE NOTICE '   • Todo lo demás funciona igual que antes';
    RAISE NOTICE '';
    RAISE NOTICE '🚀 PRÓXIMOS PASOS:';
    RAISE NOTICE '   1. Hacer Hot Restart en Dreamflow';
    RAISE NOTICE '   2. Probar registro de restaurante';
    RAISE NOTICE '   3. Verificar que se cree en user_preferences';
  ELSE
    RAISE WARNING '⚠️  RPC no encontrada - revisar manualmente';
  END IF;
  
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
END $$;

-- ============================================================================
-- FIN
-- ============================================================================
