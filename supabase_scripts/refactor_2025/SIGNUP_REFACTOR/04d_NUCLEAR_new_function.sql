-- ============================================================================
-- SOLUCIÓN NUCLEAR: CREAR NUEVA FUNCIÓN CON NOMBRE DIFERENTE
-- ============================================================================
-- Descripción: PostgreSQL parece estar usando una versión en caché.
--              Creamos una función completamente nueva con otro nombre.
-- ============================================================================

-- ============================================================================
-- PASO 1: Eliminar trigger y función viejos
-- ============================================================================

DROP TRIGGER IF EXISTS master_handle_new_user ON auth.users CASCADE;
DROP FUNCTION IF EXISTS public.master_handle_signup() CASCADE;

-- ============================================================================
-- PASO 2: Crear función NUEVA con nombre DIFERENTE
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
  -- NORMALIZACIÓN DE ROLES - FORZAR A ESPAÑOL
  -- ========================================================================
  -- Si viene en inglés, convertir a español
  -- Si viene en español, dejar como está
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
    ELSE 'cliente'  -- Default: cliente
  END;

  -- Log START
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_new_user_signup_v2', 'START', v_role, NEW.id, v_email, 
          jsonb_build_object('input_role', v_metadata->>'role', 'normalized_role', v_role));

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
      
      -- 2.1 Crear client_profile
      INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
      VALUES (NEW.id, 'active', now(), now())
      ON CONFLICT (user_id) DO UPDATE 
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_new_user_signup_v2', 'PROFILE_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('table', 'client_profiles'));

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
-- PASO 3: Crear trigger apuntando a la nueva función
-- ============================================================================

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user_signup_v2();

-- ============================================================================
-- PASO 4: Verificación
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ FUNCIÓN Y TRIGGER RECREADOS';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Nueva función: handle_new_user_signup_v2()';
  RAISE NOTICE 'Nuevo trigger: on_auth_user_created';
  RAISE NOTICE '';
  RAISE NOTICE '🚀 Ahora ejecuta un test simple:';
  RAISE NOTICE '   07c_simple_test.sql';
  RAISE NOTICE '';
END $$;
