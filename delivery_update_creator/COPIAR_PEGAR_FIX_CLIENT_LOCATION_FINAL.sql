-- ============================================================================
-- 🔧 FIX QUIRÚRGICO FINAL: Ubicación en client_profiles
-- ============================================================================
-- PROBLEMA IDENTIFICADO:
--   La tabla 'client_profiles' NO está guardando:
--   - lat (latitud)
--   - lon (longitud)
--   - address_structured (JSON estructurado)
--
-- DIAGNÓSTICO COMPLETO:
--   ✅ Flutter SÍ envía los datos correctamente en userData
--   ✅ Los datos llegan a raw_user_meta_data de auth.users
--   ❌ El trigger handle_new_user_signup_v2() NO los está capturando
--
-- SOLUCIÓN:
--   Actualizar SOLO la sección CLIENT del trigger para capturar y guardar
--   lat, lon y address_structured desde raw_user_meta_data
--
-- ⚠️ QUIRÚRGICO: NO toca código de restaurant ni delivery_agent
-- ============================================================================

BEGIN;

-- ============================================================================
-- PASO 1: Actualizar la función del trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user_signup_v2()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_email TEXT;
  v_role TEXT;
  v_name TEXT;
  v_phone TEXT;
  v_address TEXT;
  v_lat DOUBLE PRECISION;
  v_lon DOUBLE PRECISION;
  v_address_structured JSONB;
  v_metadata JSONB;
BEGIN
  -- ========================================================================
  -- EXTRAER METADATA DE auth.users
  -- ========================================================================
  
  v_email := NEW.email;
  v_metadata := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
  v_role := COALESCE(v_metadata->>'role', 'cliente');
  v_name := COALESCE(v_metadata->>'name', split_part(v_email, '@', 1));
  v_phone := v_metadata->>'phone';
  v_address := v_metadata->>'address';
  
  -- ========================================================================
  -- 🔥 CAPTURAR UBICACIÓN (CLIENTE)
  -- ========================================================================
  
  -- Capturar lat con conversión segura
  BEGIN
    v_lat := CASE 
      WHEN v_metadata->>'lat' IS NOT NULL AND v_metadata->>'lat' != '' 
      THEN (v_metadata->>'lat')::DOUBLE PRECISION
      ELSE NULL
    END;
  EXCEPTION WHEN OTHERS THEN
    v_lat := NULL;
  END;
  
  -- Capturar lon con conversión segura
  BEGIN
    v_lon := CASE 
      WHEN v_metadata->>'lon' IS NOT NULL AND v_metadata->>'lon' != '' 
      THEN (v_metadata->>'lon')::DOUBLE PRECISION
      ELSE NULL
    END;
  EXCEPTION WHEN OTHERS THEN
    v_lon := NULL;
  END;
  
  -- Capturar address_structured (JSONB)
  v_address_structured := CASE
    WHEN v_metadata->'address_structured' IS NOT NULL 
    THEN v_metadata->'address_structured'
    ELSE NULL
  END;

  -- ========================================================================
  -- NORMALIZACIÓN DE ROLES (español → inglés)
  -- ========================================================================
  
  v_role := CASE lower(v_role)
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

  -- Log inicial con todos los datos capturados
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_new_user_signup_v2', 'START', v_role, NEW.id, v_email, 
          jsonb_build_object(
            'input_role', v_metadata->>'role', 
            'normalized_role', v_role,
            'name', v_name,
            'phone', v_phone,
            'address', v_address,
            'lat', v_lat,
            'lon', v_lon,
            'has_coordinates', v_lat IS NOT NULL AND v_lon IS NOT NULL,
            'has_address_structured', v_address_structured IS NOT NULL,
            'raw_metadata_keys', jsonb_object_keys(v_metadata)
          ));

  -- ========================================================================
  -- CREAR REGISTRO EN public.users
  -- ========================================================================
  
  INSERT INTO public.users (id, email, role, name, phone, created_at, updated_at, email_confirm)
  VALUES (
    NEW.id, 
    v_email, 
    v_role, 
    v_name, 
    v_phone, 
    now(), 
    now(), 
    NEW.email_confirmed_at IS NOT NULL
  )
  ON CONFLICT (id) DO UPDATE
  SET 
    email = EXCLUDED.email,
    role = EXCLUDED.role,
    name = EXCLUDED.name,
    phone = EXCLUDED.phone,
    email_confirm = EXCLUDED.email_confirm,
    updated_at = now();

  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_new_user_signup_v2', 'USER_CREATED', v_role, NEW.id, v_email, 
          jsonb_build_object('name', v_name, 'phone', v_phone));

  -- ========================================================================
  -- CREAR PERFILES SEGÚN ROL
  -- ========================================================================
  
  CASE v_role
    
    -- ======================================================================
    -- 🎯 ROL: CLIENT (AQUÍ ESTÁ EL FIX)
    -- ======================================================================
    WHEN 'client' THEN
      
      -- Crear client_profile CON UBICACIÓN ✅
      INSERT INTO public.client_profiles (
        user_id, 
        status, 
        address,
        lat,
        lon,
        address_structured,
        created_at, 
        updated_at
      )
      VALUES (
        NEW.id, 
        'active',
        v_address,
        v_lat,
        v_lon,
        v_address_structured,
        now(), 
        now()
      )
      ON CONFLICT (user_id) DO UPDATE 
      SET 
        address = COALESCE(EXCLUDED.address, client_profiles.address),
        lat = COALESCE(EXCLUDED.lat, client_profiles.lat),
        lon = COALESCE(EXCLUDED.lon, client_profiles.lon),
        address_structured = COALESCE(EXCLUDED.address_structured, client_profiles.address_structured),
        updated_at = now();

      -- Log con detalles de ubicación guardada
      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'CLIENT_PROFILE_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object(
                'table', 'client_profiles',
                'address_saved', v_address,
                'lat_saved', v_lat,
                'lon_saved', v_lon,
                'address_structured_saved', v_address_structured
              ));

      -- Crear account
      INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
      VALUES (NEW.id, 'client', 0.0, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'ACCOUNT_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('account_type', 'client'));

      -- Crear user_preferences
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO NOTHING;

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'USER_PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);
    
    -- ======================================================================
    -- 🍔 ROL: RESTAURANT (NO SE TOCA)
    -- ======================================================================
    WHEN 'restaurant' THEN
      
      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'RESTAURANT_SKIPPED', v_role, NEW.id, v_email, 
              jsonb_build_object('reason', 'Se usa RPC register_restaurant_atomic()'));
    
    -- ======================================================================
    -- 🚗 ROL: DELIVERY_AGENT (NO SE TOCA)
    -- ======================================================================
    WHEN 'delivery_agent' THEN
      
      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'DELIVERY_SKIPPED', v_role, NEW.id, v_email, 
              jsonb_build_object('reason', 'Se usa RPC register_delivery_agent_atomic()'));
    
    -- ======================================================================
    -- 👑 ROL: ADMIN (NO SE TOCA)
    -- ======================================================================
    WHEN 'admin' THEN
      
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO NOTHING;

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'ADMIN_PROFILE_CREATED', v_role, NEW.id, v_email, NULL);
    
    -- ======================================================================
    -- ⚠️ ROL INVÁLIDO
    -- ======================================================================
    ELSE
      
      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'ERROR_INVALID_ROLE', v_role, NEW.id, v_email, 
              jsonb_build_object('invalid_role', v_role));
      
      RAISE EXCEPTION 'Rol inválido: %. Los roles permitidos son: client, restaurant, delivery_agent, admin', v_role;
      
  END CASE;

  -- ========================================================================
  -- LOG SUCCESS
  -- ========================================================================
  
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_new_user_signup_v2', 'SUCCESS', v_role, NEW.id, v_email, 
          jsonb_build_object('completed_at', now()));

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    -- Log ERROR detallado
    INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
    VALUES ('handle_new_user_signup_v2', 'ERROR', v_role, NEW.id, v_email, 
            jsonb_build_object(
              'error_message', SQLERRM,
              'error_state', SQLSTATE,
              'error_detail', SQLERRM
            ));
    
    RAISE;
    
END;
$function$;

-- ============================================================================
-- PASO 2: Verificar que el trigger existe y está activo
-- ============================================================================

DO $$
DECLARE
  v_trigger_exists BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 
    FROM information_schema.triggers
    WHERE event_object_schema = 'auth'
    AND event_object_table = 'users'
    AND trigger_name = 'on_auth_user_created'
  ) INTO v_trigger_exists;

  IF v_trigger_exists THEN
    RAISE NOTICE '✅ Trigger on_auth_user_created ya está activo';
  ELSE
    RAISE NOTICE '⚠️ Creando trigger on_auth_user_created...';
    
    CREATE TRIGGER on_auth_user_created
      AFTER INSERT ON auth.users
      FOR EACH ROW
      EXECUTE FUNCTION public.handle_new_user_signup_v2();
    
    RAISE NOTICE '✅ Trigger on_auth_user_created creado correctamente';
  END IF;
END $$;

COMMIT;

-- ============================================================================
-- ✅ VERIFICACIÓN POST-DEPLOYMENT
-- ============================================================================

-- Verificar columnas de ubicación en client_profiles
SELECT 
  '✅ COLUMNAS DE UBICACIÓN' AS check_type,
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'client_profiles'
  AND column_name IN ('address', 'lat', 'lon', 'address_structured')
ORDER BY ordinal_position;

-- ============================================================================
-- 📋 RESUMEN EJECUTIVO
-- ============================================================================

SELECT 
  '✅ FIX COMPLETADO EXITOSAMENTE' AS status,
  'El trigger ahora captura lat, lon y address_structured para clientes' AS description,
  'Registra un nuevo cliente desde Flutter y verifica los datos' AS next_step;

-- ============================================================================
-- 🧪 INSTRUCCIONES DE PRUEBA
-- ============================================================================
--
-- 1. EJECUTA ESTE SCRIPT en Supabase SQL Editor (Run)
-- 2. VERIFICA que no hay errores
-- 3. REGISTRA un nuevo cliente desde la app Flutter
-- 4. VERIFICA los datos guardados con esta query:
--
--    SELECT 
--      u.email,
--      cp.address,
--      cp.lat,
--      cp.lon,
--      cp.address_structured,
--      cp.created_at
--    FROM public.client_profiles cp
--    JOIN public.users u ON u.id = cp.user_id
--    ORDER BY cp.created_at DESC
--    LIMIT 5;
--
-- 5. REVISA los logs de debug (opcional):
--
--    SELECT * 
--    FROM public.debug_user_signup_log 
--    WHERE role = 'client'
--    ORDER BY created_at DESC 
--    LIMIT 10;
--
-- ============================================================================
-- ⚠️ NOTAS IMPORTANTES
-- ============================================================================
--
-- - Este script NO afecta registros de restaurant ni delivery_agent
-- - Solo modifica el comportamiento para role='client'
-- - Los logs se guardan en debug_user_signup_log para debugging
-- - Si lat/lon vienen como NULL, se guardan como NULL (válido)
-- - La función es idempotente (se puede correr múltiples veces)
--
-- ============================================================================
