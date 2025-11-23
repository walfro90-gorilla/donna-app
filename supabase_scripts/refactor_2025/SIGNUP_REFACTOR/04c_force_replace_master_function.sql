-- ============================================================================
-- HOTFIX 04c: FORZAR REEMPLAZO TOTAL DE master_handle_signup()
-- ============================================================================
-- Descripción: Elimina TODAS las versiones de la función y la recrea desde
--              cero con la normalización correcta (español: cliente/restaurante/repartidor)
-- ============================================================================

-- ============================================================================
-- PASO 1: Eliminar TODAS las versiones de la función
-- ============================================================================

DO $$
DECLARE
  v_function_count INT;
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔧 ELIMINANDO TODAS LAS VERSIONES DE master_handle_signup()';
  RAISE NOTICE '========================================';
  
  -- Contar cuántas versiones existen
  SELECT COUNT(*) INTO v_function_count
  FROM pg_proc
  WHERE proname = 'master_handle_signup';
  
  RAISE NOTICE 'Versiones encontradas: %', v_function_count;
  
  -- Eliminar todas las versiones
  DROP FUNCTION IF EXISTS public.master_handle_signup() CASCADE;
  
  RAISE NOTICE '✅ Función eliminada';
  
END $$;

-- ============================================================================
-- PASO 2: Crear la función desde cero con normalización correcta
-- ============================================================================

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

  -- Normalizar rol a valores estándar EN ESPAÑOL
  v_role := CASE lower(v_role)
    WHEN 'client' THEN 'cliente'
    WHEN 'restaurant' THEN 'restaurante'
    WHEN 'delivery_agent' THEN 'repartidor'
    WHEN 'delivery' THEN 'repartidor'
    ELSE lower(v_role)
  END;

  -- Log START
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('master_handle_signup', 'START', v_role, NEW.id, v_email, v_metadata);

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
  VALUES ('master_handle_signup', 'USER_CREATED', v_role, NEW.id, v_email, 
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
      VALUES ('master_handle_signup', 'PROFILE_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('table', 'client_profiles'));

      -- 2.2 Crear account
      INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
      VALUES (NEW.id, 'client', 0.0, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('master_handle_signup', 'ACCOUNT_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('account_type', 'client'));

      -- 2.3 Crear user_preferences
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('master_handle_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

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
      VALUES ('master_handle_signup', 'RESTAURANT_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('status', 'pending'));

      -- 2.2 Crear user_preferences
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('master_handle_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

      -- NOTA: La cuenta (account) se crea cuando el admin aprueba el restaurante

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
      VALUES ('master_handle_signup', 'DELIVERY_PROFILE_CREATED', v_role, NEW.id, v_email, 
              jsonb_build_object('account_state', 'pending'));

      -- 2.2 Crear user_preferences
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('master_handle_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);

      -- NOTA: La cuenta (account) se crea cuando el admin aprueba al repartidor

    -- ======================================================================
    -- ROL: ADMIN
    -- ======================================================================
    WHEN 'admin' THEN
      
      -- Solo crear user_preferences (los admins no necesitan profiles ni cuentas)
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now())
      ON CONFLICT (user_id) DO UPDATE
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
      VALUES ('master_handle_signup', 'ADMIN_SETUP', v_role, NEW.id, v_email, NULL);

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
    
    -- Re-lanzar el error para que Supabase Auth lo maneje
    RAISE;
    
END;
$function$;

-- ============================================================================
-- PASO 3: Recrear el trigger
-- ============================================================================

DROP TRIGGER IF EXISTS master_handle_new_user ON auth.users;

CREATE TRIGGER master_handle_new_user
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.master_handle_signup();

-- ============================================================================
-- PASO 4: Verificación
-- ============================================================================

DO $$
DECLARE
  v_function_body TEXT;
  v_has_normalization BOOLEAN;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ FUNCIÓN Y TRIGGER RECREADOS';
  RAISE NOTICE '========================================';
  
  -- Verificar que la función tenga la normalización correcta
  SELECT pg_get_functiondef(oid) INTO v_function_body
  FROM pg_proc
  WHERE proname = 'master_handle_signup'
    AND pronamespace = 'public'::regnamespace;
  
  v_has_normalization := v_function_body LIKE '%WHEN ''client'' THEN ''cliente''%';
  
  IF v_has_normalization THEN
    RAISE NOTICE '✅ Normalización correcta verificada (client -> cliente)';
  ELSE
    RAISE EXCEPTION '❌ ERROR: La función NO tiene la normalización correcta';
  END IF;
  
  RAISE NOTICE '';
  RAISE NOTICE '🚀 Ahora ejecuta: 07b_hotfix_verify_trigger.sql';
  RAISE NOTICE '';
  
END $$;
