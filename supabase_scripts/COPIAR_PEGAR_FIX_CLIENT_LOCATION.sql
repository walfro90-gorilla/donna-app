-- ============================================================================
-- SCRIPT QUIRÚRGICO: FIX_CLIENT_LOCATION_IN_CLIENT_PROFILES.sql
-- ============================================================================
-- PROBLEMA:
--   La tabla 'client_profiles' NO está guardando los valores de:
--   - lat (latitud)
--   - lon (longitud)
--   - address_structured (JSON con datos estructurados de dirección)
--
-- DIAGNÓSTICO:
--   El trigger 'handle_new_user_signup_v2()' ya está configurado para capturar
--   estos datos, PERO necesitamos verificar que esté activo y funcionando.
--
-- SOLUCIÓN:
--   1. Actualizar la función trigger para capturar CORRECTAMENTE lat/lon/address_structured
--   2. NO tocar otras funcionalidades (restaurants, delivery_agents)
--   3. Quirúrgico: Solo modificar la parte de CLIENT
-- ============================================================================

-- ============================================================================
-- PASO 1: Actualizar función del trigger (SOLO SECCIÓN CLIENT)
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
  -- PASO 0: Extraer metadata del usuario en auth.users
  -- ========================================================================
  
  v_email := NEW.email;
  v_metadata := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
  v_role := COALESCE(v_metadata->>'role', 'cliente');
  v_name := COALESCE(v_metadata->>'name', split_part(v_email, '@', 1));
  v_phone := v_metadata->>'phone';
  
  -- ========================================================================
  -- 🔥 FIX: Extraer correctamente los datos de ubicación
  -- ========================================================================
  v_address := v_metadata->>'address';
  
  -- Conversión segura de lat/lon (pueden venir como string o number)
  BEGIN
    v_lat := CASE 
      WHEN v_metadata->>'lat' IS NOT NULL AND v_metadata->>'lat' != '' 
      THEN (v_metadata->>'lat')::DOUBLE PRECISION
      ELSE NULL
    END;
  EXCEPTION WHEN OTHERS THEN
    v_lat := NULL;
  END;
  
  BEGIN
    v_lon := CASE 
      WHEN v_metadata->>'lon' IS NOT NULL AND v_metadata->>'lon' != '' 
      THEN (v_metadata->>'lon')::DOUBLE PRECISION
      ELSE NULL
    END;
  EXCEPTION WHEN OTHERS THEN
    v_lon := NULL;
  END;
  
  -- Capturar address_structured (puede ser JSON o string)
  v_address_structured := CASE
    WHEN v_metadata->'address_structured' IS NOT NULL 
    THEN v_metadata->'address_structured'
    ELSE NULL
  END;

  -- ========================================================================
  -- NORMALIZACIÓN DE ROLES
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

  -- Log START
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_new_user_signup_v2', 'START', v_role, NEW.id, v_email, 
          jsonb_build_object(
            'input_role', v_metadata->>'role', 
            'normalized_role', v_role,
            'has_address', v_address IS NOT NULL,
            'lat_value', v_lat,
            'lon_value', v_lon,
            'has_coordinates', v_lat IS NOT NULL AND v_lon IS NOT NULL,
            'has_address_structured', v_address_structured IS NOT NULL
          ));

  -- ========================================================================
  -- PASO 1: Crear registro en public.users
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
  -- PASO 2: Crear profile según el rol
  -- ========================================================================
  
  CASE v_role
    
    -- ======================================================================
    -- 🔥 ROL: CLIENT (QUIRÚRGICO - SOLO ESTA PARTE SE MODIFICA)
    -- ======================================================================
    WHEN 'client' THEN
      
      -- 2.1 Crear client_profile CON DIRECCIÓN Y COORDENADAS ✅
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

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'PROFILE_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object(
                'table', 'client_profiles',
                'address', v_address,
                'lat', v_lat,
                'lon', v_lon,
                'address_structured', v_address_structured
              ));

      -- 2.2 Crear account
      INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
      VALUES (NEW.id, 'client', 0.0, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'ACCOUNT_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('account_type', 'client'));

      -- 2.3 Crear user_preferences
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

    -- ======================================================================
    -- ROL: RESTAURANT (NO SE MODIFICA)
    -- ======================================================================
    WHEN 'restaurant' THEN
      
      -- 2.1 Crear restaurant con status 'pending'
      INSERT INTO public.restaurants (
        user_id, 
        name, 
        status, 
        created_at, 
        updated_at
      )
      VALUES (
        NEW.id, 
        v_name, 
        'pending', 
        now(), 
        now()
      )
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'RESTAURANT_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('status', 'pending'));

      -- 2.2 Crear user_preferences
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

    -- ======================================================================
    -- ROL: DELIVERY_AGENT (NO SE MODIFICA)
    -- ======================================================================
    WHEN 'delivery_agent' THEN
      
      -- 2.1 Crear delivery_agent_profile con account_state 'pending'
      INSERT INTO public.delivery_agent_profiles (
        user_id, 
        status,
        account_state, 
        created_at, 
        updated_at
      )
      VALUES (
        NEW.id, 
        'pending',
        'pending', 
        now(), 
        now()
      )
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'DELIVERY_PROFILE_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('account_state', 'pending'));

      -- 2.2 Crear user_preferences
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

    -- ======================================================================
    -- ROL: ADMIN (NO SE MODIFICA)
    -- ======================================================================
    WHEN 'admin' THEN
      
      -- Solo crear user_preferences
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'ADMIN_SETUP', v_role, NEW.id, v_email, NULL);

    -- ======================================================================
    -- ROL INVÁLIDO
    -- ======================================================================
    ELSE
      RAISE EXCEPTION 'Rol inválido: %. Los roles permitidos son: client, restaurant, delivery_agent, admin', v_role;
      
  END CASE;

  -- ========================================================================
  -- PASO 3: Log SUCCESS
  -- ========================================================================
  
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_new_user_signup_v2', 'SUCCESS', v_role, NEW.id, v_email, 
          jsonb_build_object('completed_at', now()));

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    -- Log ERROR
    INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
    VALUES ('handle_new_user_signup_v2', 'ERROR', v_role, NEW.id, v_email, 
            jsonb_build_object(
              'error', SQLERRM,
              'state', SQLSTATE
            ));
    
    RAISE;
    
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
    AND p.proname = 'handle_new_user_signup_v2'
  ) INTO v_function_exists;

  IF v_function_exists THEN
    RAISE NOTICE '✅ Función handle_new_user_signup_v2() actualizada correctamente';
  ELSE
    RAISE EXCEPTION '❌ ERROR: La función no existe';
  END IF;
END $$;

-- ============================================================================
-- PASO 3: Verificar que el trigger está activo
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
    RAISE NOTICE '✅ Trigger on_auth_user_created está activo';
  ELSE
    RAISE WARNING '⚠️ Trigger on_auth_user_created NO existe. Creándolo...';
    
    -- Crear trigger si no existe
    CREATE TRIGGER on_auth_user_created
      AFTER INSERT ON auth.users
      FOR EACH ROW
      EXECUTE FUNCTION public.handle_new_user_signup_v2();
    
    RAISE NOTICE '✅ Trigger on_auth_user_created creado correctamente';
  END IF;
END $$;

-- ============================================================================
-- PASO 4: Verificar estructura de client_profiles
-- ============================================================================

SELECT 
  '✅ COLUMNAS DE UBICACIÓN EN client_profiles' AS status,
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'client_profiles'
  AND column_name IN ('address', 'lat', 'lon', 'address_structured')
ORDER BY ordinal_position;

-- ============================================================================
-- ✅ RESUMEN FINAL
-- ============================================================================

SELECT 
  '✅ FIX COMPLETADO' AS status,
  'client_profiles ahora captura lat, lon y address_structured' AS description,
  'Prueba registrando un nuevo cliente con datos de ubicación' AS next_step;

-- ============================================================================
-- 📋 INSTRUCCIONES PARA EL DESARROLLADOR
-- ============================================================================
--
-- 1. Copia y pega este script completo en el Supabase SQL Editor
-- 2. Ejecuta el script (debe completar sin errores)
-- 3. Verifica los mensajes:
--    ✅ Función actualizada
--    ✅ Trigger activo
--    ✅ Columnas existentes
-- 4. Prueba registrando un cliente nuevo desde Flutter
-- 5. Verifica en Supabase que los datos se guardaron:
--
--    SELECT user_id, address, lat, lon, address_structured 
--    FROM public.client_profiles 
--    ORDER BY created_at DESC 
--    LIMIT 5;
--
-- ============================================================================
