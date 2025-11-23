-- ============================================================================
-- SOLUCIÓN FINAL: CAMBIAR TODO A INGLÉS
-- ============================================================================
-- Decisión: La base de datos ya está insertando roles en inglés.
--           Es más seguro adaptar el constraint y las funciones a inglés.
-- ============================================================================

-- ============================================================================
-- PASO 1: Actualizar constraint para aceptar roles en INGLÉS
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔧 CAMBIANDO A ROLES EN INGLÉS';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  
  -- Eliminar constraint viejo
  ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check CASCADE;
  
  RAISE NOTICE '✅ Constraint viejo eliminado';
  
  -- Crear constraint nuevo con valores EN INGLÉS
  ALTER TABLE public.users
  ADD CONSTRAINT users_role_check 
  CHECK (role IN ('client', 'restaurant', 'delivery_agent', 'admin'));
  
  RAISE NOTICE '✅ Constraint nuevo creado (inglés)';
  RAISE NOTICE '';
  
END $$;

-- ============================================================================
-- PASO 2: Eliminar funciones y triggers viejos
-- ============================================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users CASCADE;
DROP TRIGGER IF EXISTS master_handle_new_user ON auth.users CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_user_signup_v2() CASCADE;
DROP FUNCTION IF EXISTS public.master_handle_signup() CASCADE;

-- ============================================================================
-- PASO 3: Crear función FINAL con roles en INGLÉS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_user_signup()
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
  -- Extraer metadata
  v_email := NEW.email;
  v_metadata := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
  v_role := COALESCE(v_metadata->>'role', 'client');  -- Default: client
  v_name := COALESCE(v_metadata->>'name', split_part(v_email, '@', 1));
  v_phone := v_metadata->>'phone';

  -- Normalizar rol a valores INGLÉS
  v_role := CASE lower(v_role)
    WHEN 'cliente' THEN 'client'
    WHEN 'client' THEN 'client'
    WHEN 'restaurante' THEN 'restaurant'
    WHEN 'restaurant' THEN 'restaurant'
    WHEN 'repartidor' THEN 'delivery_agent'
    WHEN 'delivery_agent' THEN 'delivery_agent'
    WHEN 'delivery' THEN 'delivery_agent'
    WHEN 'admin' THEN 'admin'
    ELSE 'client'
  END;

  -- Log START
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_user_signup', 'START', v_role, NEW.id, v_email, 
          jsonb_build_object('input_role', v_metadata->>'role', 'normalized_role', v_role));

  -- Crear registro en public.users
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
  VALUES ('handle_user_signup', 'USER_CREATED', v_role, NEW.id, v_email, 
          jsonb_build_object('name', v_name, 'phone', v_phone));

  -- Crear profiles según el rol
  CASE v_role
    
    WHEN 'client' THEN
      
      INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
      VALUES (NEW.id, 'active', now(), now())
      ON CONFLICT (user_id) DO UPDATE 
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_user_signup', 'PROFILE_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('table', 'client_profiles'));

      INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
      VALUES (NEW.id, 'client', 0.0, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_user_signup', 'ACCOUNT_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('account_type', 'client'));

      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_user_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

    WHEN 'restaurant' THEN
      
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
      VALUES ('handle_user_signup', 'RESTAURANT_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('status', 'pending'));

      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_user_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

    WHEN 'delivery_agent' THEN
      
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
      VALUES ('handle_user_signup', 'DELIVERY_PROFILE_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('account_state', 'pending'));

      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_user_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

    WHEN 'admin' THEN
      
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_user_signup', 'ADMIN_SETUP', v_role, NEW.id, v_email, NULL);

    ELSE
      RAISE EXCEPTION 'Rol inválido: %. Los roles permitidos son: client, restaurant, delivery_agent, admin', v_role;
      
  END CASE;

  -- Log SUCCESS
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_user_signup', 'SUCCESS', v_role, NEW.id, v_email, 
          jsonb_build_object('completed_at', now()));

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
    VALUES ('handle_user_signup', 'ERROR', v_role, NEW.id, v_email, 
            jsonb_build_object(
              'error', SQLERRM,
              'state', SQLSTATE
            ));
    RAISE;
    
END;
$function$;

-- ============================================================================
-- PASO 4: Crear trigger
-- ============================================================================

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_user_signup();

-- ============================================================================
-- PASO 5: Test inmediato
-- ============================================================================

DO $$
DECLARE
  v_test_email TEXT := 'test_final_' || extract(epoch from now())::bigint || '@test.com';
  v_auth_id UUID := uuid_generate_v4();
  v_user_role TEXT;
  v_profile_exists BOOLEAN;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🧪 TEST FINAL CON INGLÉS';
  RAISE NOTICE '========================================';
  RAISE NOTICE '📧 Email: %', v_test_email;
  RAISE NOTICE '';
  
  -- Test con 'client' (inglés)
  INSERT INTO auth.users (
    id, 
    email, 
    raw_user_meta_data, 
    created_at, 
    updated_at,
    aud,
    role,
    encrypted_password
  )
  VALUES (
    v_auth_id, 
    v_test_email, 
    jsonb_build_object('role', 'client', 'name', 'Test Final Client'),
    now(), 
    now(),
    'authenticated',
    'authenticated',
    crypt('test_password_123', gen_salt('bf'))
  );
  
  PERFORM pg_sleep(0.5);
  
  SELECT role INTO v_user_role FROM public.users WHERE id = v_auth_id;
  SELECT EXISTS(SELECT 1 FROM public.client_profiles WHERE user_id = v_auth_id) INTO v_profile_exists;
  
  RAISE NOTICE '📊 RESULTADOS:';
  RAISE NOTICE '   public.users.role: %', COALESCE(v_user_role, 'NO EXISTE');
  RAISE NOTICE '   client_profiles exists: %', v_profile_exists;
  RAISE NOTICE '';
  
  IF v_user_role = 'client' AND v_profile_exists THEN
    RAISE NOTICE '✅✅✅ TEST PASADO ✅✅✅';
    RAISE NOTICE '';
    RAISE NOTICE '🎉 SIGNUP AUTOMÁTICO FUNCIONANDO CORRECTAMENTE';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Próximos pasos:';
    RAISE NOTICE '   1. Actualizar Flutter para usar roles en inglés';
    RAISE NOTICE '   2. Migrar datos existentes (si es necesario)';
    RAISE NOTICE '   3. Ejecutar: 07_validation_test_signup.sql (actualizado)';
  ELSE
    RAISE EXCEPTION '❌ TEST FALLIDO: role=%, profile_exists=%', v_user_role, v_profile_exists;
  END IF;
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ ERROR: %', SQLERRM;
    RAISE NOTICE 'Ver logs: SELECT * FROM debug_user_signup_log WHERE email = ''%'';', v_test_email;
    RAISE;
END $$;
