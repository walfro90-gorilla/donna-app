-- ============================================================================
-- HOTFIX: CORREGIR master_handle_signup() - PG_EXCEPTION_CONTEXT
-- ============================================================================
-- Descripción: Corrige el error "column pg_exception_context does not exist"
--              en el bloque EXCEPTION de master_handle_signup().
--
-- Razón: PG_EXCEPTION_CONTEXT no es una variable estándar de PostgreSQL.
--        Solo SQLERRM y SQLSTATE están disponibles en bloques EXCEPTION.
-- ============================================================================

-- ============================================================================
-- RECREAR FUNCIÓN CON LA CORRECCIÓN
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
  v_name := COALESCE(v_metadata->>'name', split_part(v_email, '@', 1)); -- Usar parte del email si no hay nombre
  v_phone := v_metadata->>'phone';

  -- Normalizar rol a valores estándar
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
    false -- Email NO confirmado aún (Supabase Auth lo actualizará después)
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

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
      VALUES ('master_handle_signup', 'CLIENT_PROFILE_CREATED', v_role, NEW.id, v_email);

      -- 2.2 Crear account para cliente (balance inicial 0)
      INSERT INTO public.accounts (id, user_id, account_type, balance, created_at, updated_at)
      VALUES (uuid_generate_v4(), NEW.id, 'client', 0.00, now(), now())
      ON CONFLICT DO NOTHING; -- Si ya existe, no hacer nada

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
      VALUES ('master_handle_signup', 'CLIENT_ACCOUNT_CREATED', v_role, NEW.id, v_email);

    -- ======================================================================
    -- ROL: RESTAURANTE
    -- ======================================================================
    WHEN 'restaurante' THEN
      
      -- 2.1 Crear registro en restaurants (status=pending, NO crear account aún)
      INSERT INTO public.restaurants (
        id, 
        user_id, 
        name, 
        status, 
        online, 
        created_at, 
        updated_at,
        commission_bps -- Default: 1500 (15%)
      )
      VALUES (
        uuid_generate_v4(), 
        NEW.id, 
        v_name || '''s Restaurant', -- Nombre temporal
        'pending', -- Requiere aprobación del admin
        false, -- No está online hasta ser aprobado
        now(), 
        now(),
        1500 -- 15% comisión por defecto
      )
      ON CONFLICT DO NOTHING; -- Si ya existe, no hacer nada

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
      VALUES ('master_handle_signup', 'RESTAURANT_CREATED', v_role, NEW.id, v_email);

      -- NOTA: El account se creará DESPUÉS cuando el admin apruebe
      --       (mediante el trigger create_account_on_user_approval o manualmente)

    -- ======================================================================
    -- ROL: REPARTIDOR
    -- ======================================================================
    WHEN 'repartidor' THEN
      
      -- 2.1 Crear delivery_agent_profile (account_state=pending, NO crear account aún)
      INSERT INTO public.delivery_agent_profiles (
        user_id, 
        status, 
        account_state, 
        created_at, 
        updated_at
      )
      VALUES (
        NEW.id, 
        'pending', -- No puede trabajar hasta completar onboarding
        'pending', -- Requiere aprobación del admin
        now(), 
        now()
      )
      ON CONFLICT (user_id) DO UPDATE 
      SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
      VALUES ('master_handle_signup', 'DELIVERY_PROFILE_CREATED', v_role, NEW.id, v_email);

      -- NOTA: El account se creará DESPUÉS cuando el admin apruebe
      --       (mediante el trigger create_account_on_user_approval o manualmente)

    -- ======================================================================
    -- ROL: ADMIN (edge case)
    -- ======================================================================
    WHEN 'admin' THEN
      
      -- Los admins NO necesitan profiles adicionales
      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
      VALUES ('master_handle_signup', 'ADMIN_USER_CREATED', v_role, NEW.id, v_email);

    -- ======================================================================
    -- ROL INVÁLIDO
    -- ======================================================================
    ELSE
      
      -- Lanzar excepción para rollback
      RAISE EXCEPTION 'Invalid role: %. Expected: cliente, restaurante, repartidor, or admin', v_role;

  END CASE;

  -- ========================================================================
  -- PASO 3: Crear user_preferences (para todos los roles)
  -- ========================================================================
  
  INSERT INTO public.user_preferences (user_id, created_at, updated_at)
  VALUES (NEW.id, now(), now())
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
  VALUES ('master_handle_signup', 'USER_PREFERENCES_CREATED', v_role, NEW.id, v_email);

  -- ========================================================================
  -- PASO 4: Log SUCCESS
  -- ========================================================================
  
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('master_handle_signup', 'SUCCESS', v_role, NEW.id, v_email,
          jsonb_build_object('completed_at', now(), 'metadata', v_metadata));

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    -- ========================================================================
    -- MANEJO DE ERRORES: Log ERROR y rollback
    -- ========================================================================
    
    -- Nota: PG_EXCEPTION_CONTEXT no existe en PostgreSQL estándar
    -- Solo usamos SQLERRM (mensaje) y SQLSTATE (código)
    INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
    VALUES ('master_handle_signup', 'ERROR', v_role, NEW.id, v_email,
            jsonb_build_object(
              'error', SQLERRM, 
              'state', SQLSTATE
            ));
    
    -- Re-lanzar el error para que Supabase Auth devuelva 500 y haga ROLLBACK
    -- Esto asegura que NO se crea nada en public.users ni en auth.users si falla
    RAISE;
END;
$function$;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ HOTFIX APLICADO';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Función: public.master_handle_signup()';
  RAISE NOTICE 'Corrección: Eliminado PG_EXCEPTION_CONTEXT del bloque EXCEPTION';
  RAISE NOTICE '';
  RAISE NOTICE '✅ Ahora puedes volver a ejecutar el script 07_validation_test_signup.sql';
  RAISE NOTICE '';
END $$;
