-- ============================================================================
-- SCRIPT: 2025-11-12_fix_client_address_final.sql
-- Descripción: Actualiza tanto el TRIGGER como el RPC para almacenar 
--              correctamente la dirección en client_profiles
-- ============================================================================
-- PROBLEMA:
--   1. master_handle_signup() NO guarda address/lat/lon/address_structured
--      en client_profiles al registrarse
--   2. ensure_user_profile_public() NO actualiza client_profiles
-- 
-- SOLUCIÓN:
--   1. Actualizar master_handle_signup() para capturar dirección desde 
--      raw_user_meta_data e insertarla en client_profiles
--   2. Actualizar ensure_user_profile_public() para TAMBIÉN actualizar
--      client_profiles cuando el rol es 'client'
-- ============================================================================

-- ============================================================================
-- PARTE 1: ACTUALIZAR TRIGGER master_handle_signup()
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
  -- Extraer metadata del usuario en auth.users
  v_email := NEW.email;
  v_metadata := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
  v_role := COALESCE(v_metadata->>'role', 'cliente');
  v_name := COALESCE(v_metadata->>'name', split_part(v_email, '@', 1));
  v_phone := v_metadata->>'phone';
  
  -- Extraer datos de dirección y geolocalización
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

  -- Normalización de roles
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

  -- Crear registro en public.users
  INSERT INTO public.users (id, email, role, name, phone, created_at, updated_at, email_confirm)
  VALUES (
    NEW.id, 
    v_email, 
    v_role, 
    v_name, 
    NULLIF(TRIM(v_phone), ''), 
    now(), 
    now(), 
    false
  )
  ON CONFLICT (id) DO UPDATE
  SET 
    email = EXCLUDED.email,
    role = EXCLUDED.role,
    name = EXCLUDED.name,
    phone = COALESCE(EXCLUDED.phone, users.phone),
    updated_at = now();

  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('master_handle_signup', 'USER_CREATED', v_role, NEW.id, v_email, 
          jsonb_build_object('name', v_name, 'phone', v_phone));

  -- Crear profile según el rol
  CASE v_role
    
    -- ROL: CLIENTE
    WHEN 'cliente' THEN
      
      -- Crear client_profile CON DIRECCIÓN Y COORDENADAS
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

    -- ROL: RESTAURANTE
    WHEN 'restaurante' THEN
      
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

      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('master_handle_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

    -- ROL: REPARTIDOR
    WHEN 'repartidor' THEN
      
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

      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('master_handle_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

    -- ROL: ADMIN
    WHEN 'admin' THEN
      
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

-- Recrear trigger si no existe
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.master_handle_signup();

-- ============================================================================
-- PARTE 2: ACTUALIZAR RPC ensure_user_profile_public()
-- ============================================================================

DROP FUNCTION IF EXISTS public.ensure_user_profile_public(uuid, text, text, text, text, text, double precision, double precision, jsonb) CASCADE;

CREATE OR REPLACE FUNCTION public.ensure_user_profile_public(
  p_user_id uuid,
  p_email text,
  p_name text DEFAULT '',
  p_role text DEFAULT 'client',
  p_phone text DEFAULT '',
  p_address text DEFAULT '',
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists boolean;
  v_is_email_confirmed boolean := false;
  v_now timestamptz := now();
  v_role text;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id is required';
  END IF;

  -- verify exists in auth.users
  PERFORM 1 FROM auth.users WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User ID % does not exist in auth.users', p_user_id;
  END IF;

  -- email confirmation flag from auth
  SELECT (email_confirmed_at IS NOT NULL) INTO v_is_email_confirmed
  FROM auth.users WHERE id = p_user_id;

  -- normalize role to español
  v_role := CASE LOWER(COALESCE(p_role, ''))
    WHEN 'client' THEN 'cliente'
    WHEN 'usuario' THEN 'cliente'
    WHEN 'cliente' THEN 'cliente'
    WHEN 'restaurant' THEN 'restaurante'
    WHEN 'restaurante' THEN 'restaurante'
    WHEN 'delivery_agent' THEN 'repartidor'
    WHEN 'repartidor' THEN 'repartidor'
    WHEN 'admin' THEN 'admin'
    ELSE 'cliente'
  END;

  -- upsert users table
  SELECT EXISTS(SELECT 1 FROM public.users WHERE id = p_user_id) INTO v_exists;
  IF NOT v_exists THEN
    INSERT INTO public.users (
      id, email, name, phone, role, email_confirm,
      created_at, updated_at
    ) VALUES (
      p_user_id,
      COALESCE(p_email, ''),
      COALESCE(p_name, ''),
      NULLIF(TRIM(p_phone), ''),
      COALESCE(v_role, 'cliente'),
      COALESCE(v_is_email_confirmed, false),
      v_now,
      v_now
    );
  ELSE
    UPDATE public.users u SET
      email = COALESCE(NULLIF(p_email, ''), u.email),
      name = COALESCE(NULLIF(p_name, ''), u.name),
      phone = COALESCE(NULLIF(TRIM(p_phone), ''), u.phone),
      role = CASE WHEN COALESCE(u.role, '') IN ('', 'cliente', 'client') THEN COALESCE(v_role, 'cliente') ELSE u.role END,
      email_confirm = COALESCE(u.email_confirm, v_is_email_confirmed),
      updated_at = v_now
    WHERE u.id = p_user_id;
  END IF;

  -- NUEVO: Si el rol es 'cliente', también actualizar client_profiles
  IF v_role = 'cliente' THEN
    INSERT INTO public.client_profiles (
      user_id,
      status,
      address,
      lat,
      lon,
      address_structured,
      created_at,
      updated_at
    ) VALUES (
      p_user_id,
      'active',
      p_address,
      p_lat,
      p_lon,
      p_address_structured,
      v_now,
      v_now
    )
    ON CONFLICT (user_id) DO UPDATE
    SET
      address = COALESCE(EXCLUDED.address, client_profiles.address),
      lat = COALESCE(EXCLUDED.lat, client_profiles.lat),
      lon = COALESCE(EXCLUDED.lon, client_profiles.lon),
      address_structured = COALESCE(EXCLUDED.address_structured, client_profiles.address_structured),
      updated_at = v_now;
  END IF;

  RETURN jsonb_build_object('success', true, 'data', jsonb_build_object('user_id', p_user_id), 'error', NULL);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_user_profile_public(
  uuid, text, text, text, text, text, double precision, double precision, jsonb
) TO anon, authenticated, service_role;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

SELECT '✅ SCRIPT COMPLETADO' as status;

SELECT 
  '✅ FUNCIÓN master_handle_signup() ACTUALIZADA' as status,
  'Ahora inserta address/lat/lon/address_structured en client_profiles' as feature;

SELECT 
  '✅ FUNCIÓN ensure_user_profile_public() ACTUALIZADA' as status,
  'Ahora también actualiza client_profiles para clientes' as feature;

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
-- NOTAS IMPORTANTES
-- ============================================================================
-- 
-- ESTE SCRIPT:
-- 1. ✅ Actualiza el trigger para que capture dirección desde raw_user_meta_data
-- 2. ✅ Actualiza el RPC para que TAMBIÉN actualice client_profiles
-- 3. ✅ Usa NULLIF para phone (evita strings vacíos)
-- 4. ✅ Usa COALESCE para preservar valores existentes
-- 5. ✅ Normaliza roles a español (cliente, restaurante, repartidor, admin)
-- 
-- FRONTEND YA ENVÍA CORRECTAMENTE:
-- - userData.address
-- - userData.lat
-- - userData.lon
-- - userData.address_structured
-- 
-- AHORA ESTOS DATOS SE GUARDARÁN EN client_profiles.
-- ============================================================================
