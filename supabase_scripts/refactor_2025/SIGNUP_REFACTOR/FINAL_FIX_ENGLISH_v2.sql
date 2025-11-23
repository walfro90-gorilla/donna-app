-- ============================================================================
-- SOLUCIÓN FINAL V2: INGLÉS + FIX CONSTRAINTS
-- ============================================================================

-- ============================================================================
-- PASO 1: Agregar constraints UNIQUE faltantes
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔧 AGREGANDO CONSTRAINTS FALTANTES';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  
  -- Agregar UNIQUE constraint en accounts.user_id (si no existe)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'accounts_user_id_key' 
      AND conrelid = 'public.accounts'::regclass
  ) THEN
    ALTER TABLE public.accounts 
    ADD CONSTRAINT accounts_user_id_key UNIQUE (user_id);
    RAISE NOTICE '✅ Constraint UNIQUE agregado a accounts.user_id';
  ELSE
    RAISE NOTICE '✅ Constraint UNIQUE ya existe en accounts.user_id';
  END IF;
  
  -- Agregar UNIQUE constraint en client_profiles.user_id (si no existe)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'client_profiles_user_id_key' 
      AND conrelid = 'public.client_profiles'::regclass
  ) THEN
    ALTER TABLE public.client_profiles 
    ADD CONSTRAINT client_profiles_user_id_key UNIQUE (user_id);
    RAISE NOTICE '✅ Constraint UNIQUE agregado a client_profiles.user_id';
  ELSE
    RAISE NOTICE '✅ Constraint UNIQUE ya existe en client_profiles.user_id';
  END IF;
  
  -- Agregar UNIQUE constraint en restaurants.user_id (si no existe)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'restaurants_user_id_key' 
      AND conrelid = 'public.restaurants'::regclass
  ) THEN
    ALTER TABLE public.restaurants 
    ADD CONSTRAINT restaurants_user_id_key UNIQUE (user_id);
    RAISE NOTICE '✅ Constraint UNIQUE agregado a restaurants.user_id';
  ELSE
    RAISE NOTICE '✅ Constraint UNIQUE ya existe en restaurants.user_id';
  END IF;
  
  -- Agregar UNIQUE constraint en delivery_agent_profiles.user_id (si no existe)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'delivery_agent_profiles_user_id_key' 
      AND conrelid = 'public.delivery_agent_profiles'::regclass
  ) THEN
    ALTER TABLE public.delivery_agent_profiles 
    ADD CONSTRAINT delivery_agent_profiles_user_id_key UNIQUE (user_id);
    RAISE NOTICE '✅ Constraint UNIQUE agregado a delivery_agent_profiles.user_id';
  ELSE
    RAISE NOTICE '✅ Constraint UNIQUE ya existe en delivery_agent_profiles.user_id';
  END IF;
  
  -- Agregar UNIQUE constraint en user_preferences.user_id (si no existe)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'user_preferences_user_id_key' 
      AND conrelid = 'public.user_preferences'::regclass
  ) THEN
    ALTER TABLE public.user_preferences 
    ADD CONSTRAINT user_preferences_user_id_key UNIQUE (user_id);
    RAISE NOTICE '✅ Constraint UNIQUE agregado a user_preferences.user_id';
  ELSE
    RAISE NOTICE '✅ Constraint UNIQUE ya existe en user_preferences.user_id';
  END IF;
  
  RAISE NOTICE '';
  
END $$;

-- ============================================================================
-- PASO 2: Actualizar constraint de roles a INGLÉS
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '🔧 Actualizando constraint de roles a inglés...';
  
  ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check CASCADE;
  
  ALTER TABLE public.users
  ADD CONSTRAINT users_role_check 
  CHECK (role IN ('client', 'restaurant', 'delivery_agent', 'admin'));
  
  RAISE NOTICE '✅ Constraint de roles actualizado';
  RAISE NOTICE '';
  
END $$;

-- ============================================================================
-- PASO 3: Eliminar funciones y triggers viejos
-- ============================================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users CASCADE;
DROP TRIGGER IF EXISTS master_handle_new_user ON auth.users CASCADE;
DROP FUNCTION IF EXISTS public.handle_user_signup() CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_user_signup_v2() CASCADE;
DROP FUNCTION IF EXISTS public.master_handle_signup() CASCADE;

-- ============================================================================
-- PASO 4: Crear función FINAL con roles en INGLÉS
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
  v_email := NEW.email;
  v_metadata := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
  v_role := COALESCE(v_metadata->>'role', 'client');
  v_name := COALESCE(v_metadata->>'name', split_part(v_email, '@', 1));
  v_phone := v_metadata->>'phone';

  -- Normalizar a INGLÉS
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

  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_user_signup', 'START', v_role, NEW.id, v_email, 
          jsonb_build_object('input_role', v_metadata->>'role', 'normalized_role', v_role));

  INSERT INTO public.users (id, email, role, name, phone, created_at, updated_at, email_confirm)
  VALUES (NEW.id, v_email, v_role, v_name, v_phone, now(), now(), false)
  ON CONFLICT (id) DO UPDATE
  SET email = EXCLUDED.email, role = EXCLUDED.role, name = EXCLUDED.name, 
      phone = EXCLUDED.phone, updated_at = now();

  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_user_signup', 'USER_CREATED', v_role, NEW.id, v_email, 
          jsonb_build_object('name', v_name, 'phone', v_phone));

  CASE v_role
    
    WHEN 'client' THEN
      
      INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
      VALUES (NEW.id, 'active', now(), now())
      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_user_signup', 'PROFILE_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('table', 'client_profiles'));

      INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
      VALUES (NEW.id, 'client', 0.0, now(), now())
      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_user_signup', 'ACCOUNT_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('account_type', 'client'));

      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_user_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

    WHEN 'restaurant' THEN
      
      INSERT INTO public.restaurants (user_id, name, status, created_at, updated_at)
      VALUES (NEW.id, v_name, 'pending', now(), now())
      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_user_signup', 'RESTAURANT_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('status', 'pending'));

      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_user_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

    WHEN 'delivery_agent' THEN
      
      INSERT INTO public.delivery_agent_profiles (user_id, account_state, created_at, updated_at)
      VALUES (NEW.id, 'pending', now(), now())
      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_user_signup', 'DELIVERY_PROFILE_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('account_state', 'pending'));

      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_user_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

    WHEN 'admin' THEN
      
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('handle_user_signup', 'ADMIN_SETUP', v_role, NEW.id, v_email, NULL);

    ELSE
      RAISE EXCEPTION 'Rol inválido: %', v_role;
      
  END CASE;

  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_user_signup', 'SUCCESS', v_role, NEW.id, v_email, 
          jsonb_build_object('completed_at', now()));

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
    VALUES ('handle_user_signup', 'ERROR', v_role, NEW.id, v_email, 
            jsonb_build_object('error', SQLERRM, 'state', SQLSTATE));
    RAISE;
    
END;
$function$;

-- ============================================================================
-- PASO 5: Crear trigger
-- ============================================================================

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_user_signup();

-- ============================================================================
-- PASO 6: Test automático
-- ============================================================================

DO $$
DECLARE
  v_test_email TEXT := 'test_v2_' || extract(epoch from now())::bigint || '@test.com';
  v_auth_id UUID := uuid_generate_v4();
  v_user_role TEXT;
  v_profile_exists BOOLEAN;
  v_account_exists BOOLEAN;
  v_prefs_exists BOOLEAN;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🧪 TEST FINAL V2';
  RAISE NOTICE '========================================';
  RAISE NOTICE '📧 Email: %', v_test_email;
  RAISE NOTICE '';
  
  INSERT INTO auth.users (
    id, email, raw_user_meta_data, created_at, updated_at, aud, role, encrypted_password
  )
  VALUES (
    v_auth_id, v_test_email, 
    jsonb_build_object('role', 'client', 'name', 'Test V2 Client'),
    now(), now(), 'authenticated', 'authenticated',
    crypt('test_password_123', gen_salt('bf'))
  );
  
  PERFORM pg_sleep(0.5);
  
  SELECT role INTO v_user_role FROM public.users WHERE id = v_auth_id;
  SELECT EXISTS(SELECT 1 FROM public.client_profiles WHERE user_id = v_auth_id) INTO v_profile_exists;
  SELECT EXISTS(SELECT 1 FROM public.accounts WHERE user_id = v_auth_id) INTO v_account_exists;
  SELECT EXISTS(SELECT 1 FROM public.user_preferences WHERE user_id = v_auth_id) INTO v_prefs_exists;
  
  RAISE NOTICE '📊 RESULTADOS:';
  RAISE NOTICE '   users.role: %', COALESCE(v_user_role, 'NO EXISTE');
  RAISE NOTICE '   client_profiles: %', v_profile_exists;
  RAISE NOTICE '   accounts: %', v_account_exists;
  RAISE NOTICE '   user_preferences: %', v_prefs_exists;
  RAISE NOTICE '';
  
  IF v_user_role = 'client' AND v_profile_exists AND v_account_exists AND v_prefs_exists THEN
    RAISE NOTICE '✅✅✅ TEST PASADO ✅✅✅';
    RAISE NOTICE '';
    RAISE NOTICE '🎉 SIGNUP AUTOMÁTICO FUNCIONANDO';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Próximos pasos:';
    RAISE NOTICE '   1. Probar signup desde Flutter';
    RAISE NOTICE '   2. Verificar que todos los roles funcionen';
  ELSE
    RAISE EXCEPTION '❌ FALLIDO: role=%, profile=%, account=%, prefs=%', 
      v_user_role, v_profile_exists, v_account_exists, v_prefs_exists;
  END IF;
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ ERROR: %', SQLERRM;
    RAISE NOTICE 'Ver: SELECT * FROM debug_user_signup_log WHERE email = ''%'';', v_test_email;
    RAISE;
END $$;
