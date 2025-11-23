-- ============================================================================
-- SCRIPT FINAL: FIX_CLIENT_LOCATION_V2.sql
-- ============================================================================
-- PROBLEMA IDENTIFICADO:
--   El RPC 'ensure_user_profile_public()' NO está guardando lat, lon y 
--   address_structured en la tabla 'client_profiles'.
--
-- CAUSA:
--   El RPC actualiza 'public.users' pero NO actualiza 'client_profiles'
--   con los datos de ubicación.
--
-- SOLUCIÓN:
--   Actualizar el RPC 'ensure_user_profile_public()' para que TAMBIÉN
--   actualice 'client_profiles' con lat, lon y address_structured cuando
--   el rol es 'client'.
-- ============================================================================

-- ============================================================================
-- PASO 1: Actualizar RPC ensure_user_profile_public
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ensure_user_profile_public(
  p_user_id UUID,
  p_email TEXT,
  p_name TEXT DEFAULT '',
  p_role TEXT DEFAULT 'client',
  p_phone TEXT DEFAULT '',
  p_address TEXT DEFAULT '',
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_address_structured JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_normalized_role TEXT;
  v_user_exists BOOLEAN;
BEGIN
  -- ========================================================================
  -- NORMALIZACIÓN DE ROLES (mismo que el trigger)
  -- ========================================================================
  
  v_normalized_role := CASE lower(p_role)
    WHEN 'client' THEN 'client'
    WHEN 'cliente' THEN 'client'
    WHEN 'restaurant' THEN 'restaurant'
    WHEN 'restaurante' THEN 'restaurant'
    WHEN 'delivery_agent' THEN 'delivery_agent'
    WHEN 'delivery' THEN 'delivery_agent'
    WHEN 'repartidor' THEN 'delivery_agent'
    WHEN 'admin' THEN 'admin'
    ELSE 'client'
  END;

  -- ========================================================================
  -- PASO 1: Verificar si el usuario ya existe en public.users
  -- ========================================================================
  
  SELECT EXISTS (
    SELECT 1 FROM public.users WHERE id = p_user_id
  ) INTO v_user_exists;

  -- ========================================================================
  -- PASO 2: Crear o actualizar el registro en public.users
  -- ========================================================================
  
  INSERT INTO public.users (
    id, 
    email, 
    role, 
    name, 
    phone, 
    created_at, 
    updated_at
  )
  VALUES (
    p_user_id,
    p_email,
    v_normalized_role,
    COALESCE(NULLIF(p_name, ''), split_part(p_email, '@', 1)),
    p_phone,
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE
  SET 
    email = EXCLUDED.email,
    role = EXCLUDED.role,
    name = COALESCE(NULLIF(EXCLUDED.name, ''), users.name),
    phone = COALESCE(NULLIF(EXCLUDED.phone, ''), users.phone),
    updated_at = now();

  -- ========================================================================
  -- PASO 3: Si es CLIENTE, actualizar también client_profiles
  -- 🔥 AQUÍ ESTÁ EL FIX PRINCIPAL 🔥
  -- ========================================================================
  
  IF v_normalized_role = 'client' THEN
    
    -- Actualizar client_profiles con los datos de ubicación
    UPDATE public.client_profiles
    SET 
      address = COALESCE(p_address, address),
      lat = COALESCE(p_lat, lat),
      lon = COALESCE(p_lon, lon),
      address_structured = COALESCE(p_address_structured, address_structured),
      updated_at = now()
    WHERE user_id = p_user_id;

    -- Log para debugging
    INSERT INTO public.debug_user_signup_log (
      source, 
      event, 
      role, 
      user_id, 
      email, 
      details
    )
    VALUES (
      'ensure_user_profile_public',
      'CLIENT_PROFILE_UPDATED',
      v_normalized_role,
      p_user_id,
      p_email,
      jsonb_build_object(
        'address', p_address,
        'lat', p_lat,
        'lon', p_lon,
        'has_address_structured', p_address_structured IS NOT NULL,
        'user_existed', v_user_exists
      )
    );
  
  END IF;

  -- ========================================================================
  -- PASO 4: Retornar éxito
  -- ========================================================================
  
  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'role', v_normalized_role,
    'data', jsonb_build_object(
      'user_id', p_user_id,
      'email', p_email,
      'role', v_normalized_role,
      'name', p_name,
      'location_updated', v_normalized_role = 'client' AND (p_lat IS NOT NULL OR p_lon IS NOT NULL)
    )
  );

EXCEPTION
  WHEN OTHERS THEN
    -- Log error
    INSERT INTO public.debug_user_signup_log (
      source, 
      event, 
      role, 
      user_id, 
      email, 
      details
    )
    VALUES (
      'ensure_user_profile_public',
      'ERROR',
      v_normalized_role,
      p_user_id,
      p_email,
      jsonb_build_object(
        'error', SQLERRM,
        'state', SQLSTATE
      )
    );
    
    -- Retornar error pero no fallar
    RETURN jsonb_build_object(
      'success', false,
      'error', SQLERRM
    );
    
END;
$function$;

-- ============================================================================
-- PASO 2: Verificar que la función se actualizó correctamente
-- ============================================================================

DO $$
DECLARE
  v_function_exists BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
    AND p.proname = 'ensure_user_profile_public'
  ) INTO v_function_exists;

  IF v_function_exists THEN
    RAISE NOTICE '✅ Función ensure_user_profile_public() actualizada correctamente';
  ELSE
    RAISE EXCEPTION '❌ ERROR: La función no existe';
  END IF;
END $$;

-- ============================================================================
-- PASO 3: PRUEBA - Crear un usuario de prueba y verificar
-- ============================================================================

-- Nota: Esta prueba es opcional, solo para verificar que todo funciona

DO $$
DECLARE
  v_test_user_id UUID := gen_random_uuid();
  v_result JSONB;
  v_lat_saved DOUBLE PRECISION;
  v_lon_saved DOUBLE PRECISION;
  v_address_structured_saved JSONB;
BEGIN
  -- 1. Crear usuario de prueba en auth.users (simulado)
  INSERT INTO public.users (id, email, role, name, created_at, updated_at)
  VALUES (v_test_user_id, 'test_cliente_fix@test.com', 'client', 'Test Cliente', now(), now());
  
  -- 2. Crear client_profile vacío (como lo hace el trigger)
  INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
  VALUES (v_test_user_id, 'active', now(), now());
  
  -- 3. Llamar al RPC con datos de ubicación
  SELECT public.ensure_user_profile_public(
    p_user_id := v_test_user_id,
    p_email := 'test_cliente_fix@test.com',
    p_name := 'Test Cliente',
    p_role := 'client',
    p_phone := '+1234567890',
    p_address := 'Test Address 123',
    p_lat := 31.6526613,
    p_lon := -106.4548494,
    p_address_structured := '{"city": "Juárez", "street": "O. de Nepal"}'::jsonb
  ) INTO v_result;
  
  RAISE NOTICE '📤 RPC Result: %', v_result;
  
  -- 4. Verificar que los datos se guardaron en client_profiles
  SELECT lat, lon, address_structured
  INTO v_lat_saved, v_lon_saved, v_address_structured_saved
  FROM public.client_profiles
  WHERE user_id = v_test_user_id;
  
  -- 5. Validar resultados
  IF v_lat_saved IS NOT NULL AND v_lon_saved IS NOT NULL THEN
    RAISE NOTICE '✅ TEST PASSED: Coordenadas guardadas correctamente';
    RAISE NOTICE '   - lat: %', v_lat_saved;
    RAISE NOTICE '   - lon: %', v_lon_saved;
    RAISE NOTICE '   - address_structured: %', v_address_structured_saved;
  ELSE
    RAISE WARNING '❌ TEST FAILED: Coordenadas NO se guardaron';
  END IF;
  
  -- 6. Limpiar datos de prueba
  DELETE FROM public.client_profiles WHERE user_id = v_test_user_id;
  DELETE FROM public.users WHERE id = v_test_user_id;
  
  RAISE NOTICE '🧹 Datos de prueba eliminados';
  
END $$;

-- ============================================================================
-- ✅ RESUMEN FINAL
-- ============================================================================

SELECT 
  '✅ FIX COMPLETADO - V2 FINAL' AS status,
  'RPC ensure_user_profile_public() ahora actualiza client_profiles con lat, lon y address_structured' AS description,
  'Prueba registrando un nuevo cliente desde Flutter' AS next_step;

-- ============================================================================
-- 📋 INSTRUCCIONES
-- ============================================================================
--
-- 1. Copia y pega este script completo en Supabase SQL Editor
-- 2. Ejecuta el script
-- 3. Verifica los mensajes:
--    ✅ Función actualizada correctamente
--    ✅ TEST PASSED: Coordenadas guardadas correctamente
-- 4. Prueba registrando un cliente nuevo desde Flutter
-- 5. Verifica en Supabase:
--
--    SELECT cp.user_id, u.email, cp.address, cp.lat, cp.lon, cp.address_structured
--    FROM public.client_profiles cp
--    JOIN public.users u ON cp.user_id = u.id
--    WHERE u.role = 'client'
--    ORDER BY cp.created_at DESC
--    LIMIT 5;
--
-- 6. También puedes ver los logs de debug:
--
--    SELECT * FROM public.debug_user_signup_log
--    WHERE event IN ('CLIENT_PROFILE_UPDATED', 'ERROR')
--    ORDER BY created_at DESC
--    LIMIT 10;
--
-- ============================================================================
