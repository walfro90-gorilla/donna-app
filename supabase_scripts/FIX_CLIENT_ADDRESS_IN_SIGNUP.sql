-- ============================================================================
-- SCRIPT: FIX_CLIENT_ADDRESS_IN_SIGNUP.sql
-- Descripción: Actualiza el trigger de signup para almacenar correctamente
--              la dirección, coordenadas y address_structured en client_profiles
-- ============================================================================
-- PROBLEMA: El trigger actual NO captura los datos de dirección del registro:
--           - address
--           - lat / lon
--           - address_structured (JSON con address_name, lat, lon)
--
-- SOLUCIÓN: Actualizar la función handle_new_user_signup_v2() para extraer
--           estos campos de raw_user_meta_data y almacenarlos en client_profiles
-- ============================================================================

-- ============================================================================
-- PASO 1: Reemplazar la función del trigger con soporte para dirección
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
  -- NUEVO: Extraer datos de dirección y geolocalización
  -- ========================================================================
  v_address := v_metadata->>'address';
  v_lat := CASE 
    WHEN v_metadata->>'lat' IS NOT NULL THEN (v_metadata->>'lat')::DOUBLE PRECISION
    ELSE NULL
  END;
  v_lon := CASE 
    WHEN v_metadata->>'lon' IS NOT NULL THEN (v_metadata->>'lon')::DOUBLE PRECISION
    ELSE NULL
  END;
  v_address_structured := v_metadata->'address_structured';

  -- ========================================================================
  -- NORMALIZACIÓN DE ROLES - FORZAR A ESPAÑOL
  -- ========================================================================
  
  v_role := CASE lower(v_role)
    WHEN 'client' THEN 'cliente'
    WHEN 'restaurant' THEN 'restaurante'
    WHEN 'delivery_agent' THEN 'repartidor'
    WHEN 'delivery' THEN 'repartidor'
    WHEN 'cliente' THEN 'cliente'
    WHEN 'restaurante' THEN 'restaurante'
    WHEN 'repartidor' THEN 'repartidor'
    WHEN 'admin' THEN 'admin'
    ELSE 'cliente'
  END;

  -- Log START
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_new_user_signup_v2', 'START', v_role, NEW.id, v_email, 
          jsonb_build_object(
            'input_role', v_metadata->>'role', 
            'normalized_role', v_role,
            'has_address', v_address IS NOT NULL,
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
    false
  )
  ON CONFLICT (id) DO UPDATE
  SET 
    email = EXCLUDED.email,
    role = EXCLUDED.role,
    name = EXCLUDED.name,
    phone = EXCLUDED.phone,
    updated_at = now();

  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_new_user_signup_v2', 'USER_CREATED', v_role, NEW.id, v_email, 
          jsonb_build_object('name', v_name, 'phone', v_phone));

  -- ========================================================================
  -- PASO 2: Crear profile según el rol
  -- ========================================================================
  
  CASE v_role
    
    -- ======================================================================
    -- ROL: CLIENTE
    -- ======================================================================
    WHEN 'cliente' THEN
      
      -- 2.1 Crear client_profile CON DIRECCIÓN Y COORDENADAS
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
    -- ROL: RESTAURANTE
    -- ======================================================================
    WHEN 'restaurante' THEN
      
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
    -- ROL: REPARTIDOR
    -- ======================================================================
    WHEN 'repartidor' THEN
      
      -- 2.1 Crear delivery_agent_profile con account_state 'pending'
      INSERT INTO public.delivery_agent_profiles (
        user_id, 
        account_state, 
        created_at, 
        updated_at
      )
      VALUES (
        NEW.id, 
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
    -- ROL: ADMIN
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
      RAISE EXCEPTION 'Rol inválido: %. Los roles permitidos son: cliente, restaurante, repartidor, admin', v_role;
      
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
-- PASO 2: Verificar que el trigger existe y está apuntando a la función
-- ============================================================================

SELECT 
  '✅ FUNCIÓN ACTUALIZADA' as status,
  'handle_new_user_signup_v2()' as function_name,
  'Ahora captura: address, lat, lon, address_structured' as new_feature;

-- Ver trigger actual
SELECT 
  trigger_name,
  event_manipulation,
  event_object_table,
  action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'auth'
  AND event_object_table = 'users'
  AND trigger_name = 'on_auth_user_created';

-- ============================================================================
-- PASO 3: Ver estructura de client_profiles para confirmar columnas
-- ============================================================================

SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'client_profiles'
  AND column_name IN ('address', 'lat', 'lon', 'address_structured')
ORDER BY ordinal_position;

-- ============================================================================
-- NOTA IMPORTANTE
-- ============================================================================
-- 
-- FRONTEND DEBE ENVIAR ESTOS DATOS AL REGISTRARSE:
-- 
-- await supabase.auth.signUp({
--   email: email,
--   password: password,
--   options: {
--     data: {
--       name: name,
--       phone: phone,
--       address: address,              // <-- NUEVO
--       lat: latitude,                 // <-- NUEVO
--       lon: longitude,                // <-- NUEVO
--       address_structured: {          // <-- NUEVO
--         address_name: address,
--         lat: latitude,
--         lon: longitude
--       }
--     }
--   }
-- });
-- 
-- ============================================================================
