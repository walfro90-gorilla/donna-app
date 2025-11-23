-- ============================================================================
-- SCRIPT: 2025-11-13_FIX_DUPLICATE_RPC_AND_SIGNUP.sql
-- Propósito: Eliminar RPCs duplicados + Reforzar master_handle_signup()
-- ============================================================================
-- PROBLEMA ACTUAL:
--   1. ❌ Existen múltiples versiones de ensure_user_profile_public()
--      → PostgREST error PGRST203: "Could not choose the best candidate function"
--   2. ❌ public.users no existe cuando el frontend intenta llamar RPCs
--      → FK constraint error en client_profiles/accounts/user_preferences
--   3. ❌ Verificación de email falla porque el flujo depende de llamadas manuales
--
-- SOLUCIÓN:
--   ✅ Eliminar TODAS las versiones de ensure_user_profile_public()
--   ✅ Crear UNA SOLA versión sin ambigüedades
--   ✅ Reforzar master_handle_signup() para garantizar public.users existe primero
--   ✅ El trigger ya crea todo → Frontend NO necesita llamar RPCs manualmente
-- ============================================================================

BEGIN;

-- ============================================================================
-- PASO 1: ELIMINAR TODAS LAS VERSIONES DE ensure_user_profile_public()
-- ============================================================================

DO $$
DECLARE
  v_func RECORD;
  v_count INT := 0;
BEGIN
  RAISE NOTICE '🔧 Eliminando todas las versiones de ensure_user_profile_public()...';
  
  -- Iterar sobre todas las versiones de la función
  FOR v_func IN
    SELECT 
      pg_get_function_identity_arguments(oid) as args,
      oid::regprocedure::text as full_signature
    FROM pg_proc
    WHERE proname = 'ensure_user_profile_public'
      AND pronamespace = 'public'::regnamespace
  LOOP
    RAISE NOTICE '  → Eliminando: %', v_func.full_signature;
    EXECUTE format('DROP FUNCTION IF EXISTS %s CASCADE', v_func.full_signature);
    v_count := v_count + 1;
  END LOOP;
  
  RAISE NOTICE '✅ Eliminadas % versiones de ensure_user_profile_public()', v_count;
END $$;

-- ============================================================================
-- PASO 2: CREAR UNA SOLA VERSIÓN DE ensure_user_profile_public()
-- ============================================================================
-- Firma limpia sin parámetros opcionales que causen ambigüedad
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ensure_user_profile_public(
  p_user_id UUID,
  p_email TEXT,
  p_name TEXT,
  p_role TEXT,
  p_phone TEXT DEFAULT NULL,
  p_address TEXT DEFAULT NULL,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_address_structured JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_role TEXT;
  v_result JSONB;
BEGIN
  -- Normalizar rol a español
  v_role := CASE lower(p_role)
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

  -- 1. Upsert en public.users (DEBE existir primero por FK constraints)
  INSERT INTO public.users (id, email, name, role, phone, created_at, updated_at, email_confirm)
  VALUES (
    p_user_id,
    p_email,
    COALESCE(NULLIF(p_name, ''), split_part(p_email, '@', 1)),
    v_role,
    p_phone,
    now(),
    now(),
    false
  )
  ON CONFLICT (id) DO UPDATE
  SET
    name = COALESCE(EXCLUDED.name, users.name),
    phone = COALESCE(EXCLUDED.phone, users.phone),
    updated_at = now();

  -- 2. Crear perfil según rol
  CASE v_role
    WHEN 'cliente' THEN
      -- Upsert client_profiles con dirección y coordenadas
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
        p_user_id,
        'active',
        p_address,
        p_lat,
        p_lon,
        p_address_structured,
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

      -- Asegurar cuenta financiera
      INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
      VALUES (p_user_id, 'client', 0.0, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

    WHEN 'restaurante' THEN
      -- Crear restaurant si no existe
      INSERT INTO public.restaurants (user_id, name, status, created_at, updated_at)
      VALUES (p_user_id, COALESCE(NULLIF(p_name, ''), 'Restaurant'), 'pending', now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

    WHEN 'repartidor' THEN
      -- Crear delivery_agent_profile si no existe
      INSERT INTO public.delivery_agent_profiles (user_id, account_state, created_at, updated_at)
      VALUES (p_user_id, 'pending', now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

    ELSE
      -- Admin o rol desconocido: solo user_preferences
      NULL;
  END CASE;

  -- 3. Asegurar user_preferences (para todos los roles)
  INSERT INTO public.user_preferences (user_id, created_at, updated_at)
  VALUES (p_user_id, now(), now())
  ON CONFLICT (user_id) DO UPDATE
  SET updated_at = now();

  -- Retornar resultado
  v_result := jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'role', v_role,
    'message', 'User profile ensured successfully'
  );

  RETURN v_result;
END;
$$;

-- Permisos
GRANT EXECUTE ON FUNCTION public.ensure_user_profile_public(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, JSONB
) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.ensure_user_profile_public IS 
'Idempotent RPC to ensure user profile exists in public.users + role-specific tables. 
Used as fallback for OAuth/email verification flows.';

-- ============================================================================
-- PASO 3: REFORZAR master_handle_signup() PARA GARANTIZAR public.users PRIMERO
-- ============================================================================

DROP FUNCTION IF EXISTS public.master_handle_signup() CASCADE;

CREATE OR REPLACE FUNCTION public.master_handle_signup()
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
  -- Extraer metadata
  v_email := NEW.email;
  v_metadata := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
  v_role := COALESCE(v_metadata->>'role', 'cliente');
  v_name := COALESCE(NULLIF(v_metadata->>'name', ''), split_part(v_email, '@', 1));
  v_phone := v_metadata->>'phone';
  
  -- Extraer dirección y coordenadas
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

  -- Normalizar rol a español
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
  VALUES ('master_handle_signup', 'START', v_role, NEW.id, v_email, 
          jsonb_build_object(
            'input_role', v_metadata->>'role', 
            'normalized_role', v_role,
            'has_address', v_address IS NOT NULL,
            'has_coordinates', v_lat IS NOT NULL AND v_lon IS NOT NULL,
            'has_address_structured', v_address_structured IS NOT NULL
          ));

  -- ========================================================================
  -- CRÍTICO: Crear public.users PRIMERO (required by FK constraints)
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
  VALUES ('master_handle_signup', 'USER_CREATED', v_role, NEW.id, v_email, 
          jsonb_build_object('name', v_name, 'phone', v_phone));

  -- ========================================================================
  -- Crear perfiles específicos según rol
  -- ========================================================================
  
  CASE v_role
    
    WHEN 'cliente' THEN
      
      -- Crear client_profile con dirección y coordenadas
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
      VALUES ('master_handle_signup', 'PROFILE_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object(
                'table', 'client_profiles',
                'address', v_address,
                'lat', v_lat,
                'lon', v_lon,
                'address_structured', v_address_structured
              ));

      -- Crear account
      INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
      VALUES (NEW.id, 'client', 0.0, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('master_handle_signup', 'ACCOUNT_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('account_type', 'client'));

      -- Crear user_preferences
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('master_handle_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

    WHEN 'restaurante' THEN
      
      -- Crear restaurant con status 'pending'
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
      VALUES ('master_handle_signup', 'RESTAURANT_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('status', 'pending'));

      -- Crear user_preferences
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('master_handle_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

    WHEN 'repartidor' THEN
      
      -- Crear delivery_agent_profile con account_state 'pending'
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
      VALUES ('master_handle_signup', 'DELIVERY_PROFILE_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('account_state', 'pending'));

      -- Crear user_preferences
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('master_handle_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

    WHEN 'admin' THEN
      
      -- Solo crear user_preferences
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('master_handle_signup', 'ADMIN_SETUP', v_role, NEW.id, v_email, NULL);

    ELSE
      RAISE EXCEPTION 'Rol inválido: %. Los roles permitidos son: cliente, restaurante, repartidor, admin', v_role;
      
  END CASE;

  -- Log SUCCESS
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('master_handle_signup', 'SUCCESS', v_role, NEW.id, v_email, 
          jsonb_build_object('completed_at', now()));

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    -- Log ERROR
    INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
    VALUES ('master_handle_signup', 'ERROR', v_role, NEW.id, v_email, 
            jsonb_build_object(
              'error', SQLERRM,
              'state', SQLSTATE
            ));
    
    RAISE;
    
END;
$function$;

-- ============================================================================
-- PASO 4: ASEGURAR QUE EL TRIGGER ESTÁ ACTIVO
-- ============================================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.master_handle_signup();

COMMIT;

-- ============================================================================
-- VERIFICACIONES FINALES
-- ============================================================================

SELECT '✅ SCRIPT EJECUTADO EXITOSAMENTE' as status;

-- Verificar función ensure_user_profile_public
SELECT 
  '✅ ensure_user_profile_public()' as function_name,
  COUNT(*) as version_count,
  'Debe ser 1' as expected
FROM pg_proc
WHERE proname = 'ensure_user_profile_public'
  AND pronamespace = 'public'::regnamespace;

-- Verificar trigger
SELECT 
  '✅ TRIGGER on_auth_user_created' as trigger_status,
  trigger_name,
  event_manipulation,
  action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'auth'
  AND event_object_table = 'users'
  AND trigger_name = 'on_auth_user_created';

-- ============================================================================
-- NOTA PARA EL EQUIPO DE FRONTEND
-- ============================================================================
-- 
-- ✅ FLUJO CORRECTO DESPUÉS DE ESTE SCRIPT:
-- 
-- 1. Usuario se registra → master_handle_signup() crea TODO automáticamente
-- 2. Usuario confirma email → session_manager solo lee los datos existentes
-- 3. Si falta algún dato (p.ej. OAuth), session_manager llama a ensure_user_profile_public()
-- 
-- ❌ REMOVER del frontend (ya no es necesario):
-- - Llamadas manuales a ensure_user_profile_public() después de verificar email
-- - Llamadas manuales a create_user_profile_public()
-- 
-- ✅ El trigger ya hace todo el trabajo pesado
-- 
-- ============================================================================
