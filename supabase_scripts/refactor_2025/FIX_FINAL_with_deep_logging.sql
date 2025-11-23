-- ===================================================================
-- 🔧 FIX DEFINITIVO CON LOGGING PROFESIONAL
-- ===================================================================
-- Este script:
-- 1. Crea tabla de logs detallada
-- 2. Actualiza ensure_client_profile_and_account() con logging extensivo
-- 3. Actualiza handle_new_user() con manejo de errores
-- ===================================================================

-- PASO 1: Crear tabla de logs si no existe
CREATE TABLE IF NOT EXISTS public.trigger_debug_log (
  id bigserial PRIMARY KEY,
  ts timestamptz DEFAULT now(),
  function_name text NOT NULL,
  user_id uuid,
  event text NOT NULL,
  details jsonb DEFAULT '{}'::jsonb,
  error_message text,
  stack_trace text
);

-- Índice para consultas rápidas
CREATE INDEX IF NOT EXISTS idx_trigger_debug_log_ts ON public.trigger_debug_log(ts DESC);
CREATE INDEX IF NOT EXISTS idx_trigger_debug_log_user_id ON public.trigger_debug_log(user_id);

-- ===================================================================
-- PASO 2: Recrear ensure_client_profile_and_account() con logging
-- ===================================================================

CREATE OR REPLACE FUNCTION public.ensure_client_profile_and_account(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_user_exists boolean;
  v_current_role text;
  v_account_id uuid;
  v_auth_user_email text;
  v_step text := 'init';
BEGIN
  -- LOG: Inicio
  INSERT INTO public.trigger_debug_log (function_name, user_id, event, details)
  VALUES ('ensure_client_profile_and_account', p_user_id, 'START', jsonb_build_object('timestamp', v_now));

  v_step := 'validate_auth_user';
  -- Validar que el usuario existe en auth.users
  SELECT email INTO v_auth_user_email FROM auth.users WHERE id = p_user_id;
  
  IF v_auth_user_email IS NULL THEN
    INSERT INTO public.trigger_debug_log (function_name, user_id, event, error_message)
    VALUES ('ensure_client_profile_and_account', p_user_id, 'ERROR', 'User not found in auth.users');
    
    RAISE EXCEPTION 'User % not found in auth.users', p_user_id;
  END IF;

  -- LOG: Usuario existe en auth
  INSERT INTO public.trigger_debug_log (function_name, user_id, event, details)
  VALUES ('ensure_client_profile_and_account', p_user_id, 'AUTH_USER_VALIDATED', 
    jsonb_build_object('email', v_auth_user_email));

  v_step := 'check_public_user';
  -- Verificar si existe en public.users
  SELECT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id), role
    INTO v_user_exists, v_current_role
  FROM public.users WHERE id = p_user_id;

  -- LOG: Estado en public.users
  INSERT INTO public.trigger_debug_log (function_name, user_id, event, details)
  VALUES ('ensure_client_profile_and_account', p_user_id, 'PUBLIC_USER_CHECK', 
    jsonb_build_object('exists', v_user_exists, 'role', v_current_role));

  -- SOLO crear perfil de cliente si no tiene un role especializado
  IF v_current_role IS NOT NULL AND v_current_role NOT IN ('', 'client', 'cliente') THEN
    INSERT INTO public.trigger_debug_log (function_name, user_id, event, details)
    VALUES ('ensure_client_profile_and_account', p_user_id, 'SKIPPED_SPECIALIZED_ROLE', 
      jsonb_build_object('role', v_current_role));
    
    RETURN jsonb_build_object('success', true, 'account_id', NULL, 'skipped', true, 'reason', 'specialized_role');
  END IF;

  v_step := 'create_or_update_user';
  -- Crear/actualizar usuario con role='client'
  IF NOT v_user_exists THEN
    INSERT INTO public.users (id, role, email, created_at, updated_at)
    VALUES (p_user_id, 'client', v_auth_user_email, v_now, v_now)
    ON CONFLICT (id) DO NOTHING;
    
    INSERT INTO public.trigger_debug_log (function_name, user_id, event, details)
    VALUES ('ensure_client_profile_and_account', p_user_id, 'USER_CREATED', 
      jsonb_build_object('role', 'client'));
  ELSE
    IF COALESCE(v_current_role, '') IN ('', 'client', 'cliente') THEN
      UPDATE public.users SET role = 'client', updated_at = v_now WHERE id = p_user_id;
      
      INSERT INTO public.trigger_debug_log (function_name, user_id, event, details)
      VALUES ('ensure_client_profile_and_account', p_user_id, 'USER_UPDATED', 
        jsonb_build_object('old_role', v_current_role, 'new_role', 'client'));
    END IF;
  END IF;

  v_step := 'create_client_profile';
  -- Asegurar profile de cliente CON STATUS
  INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
  VALUES (p_user_id, 'active', v_now, v_now)
  ON CONFLICT (user_id) DO UPDATE
    SET updated_at = EXCLUDED.updated_at,
        status = COALESCE(client_profiles.status, 'active');

  -- LOG: Profile creado
  INSERT INTO public.trigger_debug_log (function_name, user_id, event, details)
  VALUES ('ensure_client_profile_and_account', p_user_id, 'CLIENT_PROFILE_CREATED', 
    jsonb_build_object('status', 'active'));

  v_step := 'create_account';
  -- Asegurar cuenta financiera tipo 'client'
  SELECT id INTO v_account_id
  FROM public.accounts
  WHERE user_id = p_user_id AND account_type = 'client'
  LIMIT 1;

  IF v_account_id IS NULL THEN
    INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
    VALUES (p_user_id, 'client', 0.0, v_now, v_now)
    RETURNING id INTO v_account_id;
    
    INSERT INTO public.trigger_debug_log (function_name, user_id, event, details)
    VALUES ('ensure_client_profile_and_account', p_user_id, 'ACCOUNT_CREATED', 
      jsonb_build_object('account_id', v_account_id, 'account_type', 'client'));
  ELSE
    INSERT INTO public.trigger_debug_log (function_name, user_id, event, details)
    VALUES ('ensure_client_profile_and_account', p_user_id, 'ACCOUNT_EXISTS', 
      jsonb_build_object('account_id', v_account_id));
  END IF;

  v_step := 'create_preferences';
  -- Asegurar user_preferences
  INSERT INTO public.user_preferences (user_id, created_at, updated_at)
  VALUES (p_user_id, v_now, v_now)
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.trigger_debug_log (function_name, user_id, event, details)
  VALUES ('ensure_client_profile_and_account', p_user_id, 'PREFERENCES_CREATED', 
    jsonb_build_object('timestamp', v_now));

  -- LOG: Éxito completo
  INSERT INTO public.trigger_debug_log (function_name, user_id, event, details)
  VALUES ('ensure_client_profile_and_account', p_user_id, 'SUCCESS', 
    jsonb_build_object('account_id', v_account_id, 'status', 'active'));

  RETURN jsonb_build_object('success', true, 'account_id', v_account_id, 'status', 'active');

EXCEPTION
  WHEN OTHERS THEN
    -- LOG: Error detallado
    INSERT INTO public.trigger_debug_log (function_name, user_id, event, error_message, stack_trace, details)
    VALUES (
      'ensure_client_profile_and_account', 
      p_user_id, 
      'ERROR_EXCEPTION', 
      SQLERRM,
      SQLSTATE,
      jsonb_build_object('step', v_step, 'timestamp', now())
    );
    
    -- Re-lanzar error para que Supabase Auth lo capture
    RAISE;
END;
$$;

-- ===================================================================
-- PASO 3: Recrear handle_new_user() con manejo robusto de errores
-- ===================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_result jsonb;
  v_error text;
BEGIN
  -- LOG: Trigger disparado
  INSERT INTO public.trigger_debug_log (function_name, user_id, event, details)
  VALUES ('handle_new_user', NEW.id, 'TRIGGER_FIRED', 
    jsonb_build_object('email', NEW.email, 'auth_id', NEW.id));

  -- Intentar crear profile + account
  BEGIN
    v_result := public.ensure_client_profile_and_account(NEW.id);
    
    -- LOG: Éxito
    INSERT INTO public.trigger_debug_log (function_name, user_id, event, details)
    VALUES ('handle_new_user', NEW.id, 'PROFILE_CREATED_SUCCESS', v_result);
    
  EXCEPTION
    WHEN OTHERS THEN
      -- LOG: Error capturado
      v_error := SQLERRM;
      INSERT INTO public.trigger_debug_log (function_name, user_id, event, error_message, stack_trace)
      VALUES ('handle_new_user', NEW.id, 'PROFILE_CREATION_ERROR', v_error, SQLSTATE);
      
      -- Re-lanzar para que Supabase lo vea
      RAISE;
  END;

  RETURN NEW;
END;
$$;

-- ===================================================================
-- PASO 4: Verificar que el trigger existe (no lo recreamos)
-- ===================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgrelid = 'auth.users'::regclass 
    AND tgname = 'on_auth_user_created'
  ) THEN
    RAISE NOTICE '⚠️  WARNING: El trigger on_auth_user_created NO EXISTE en auth.users';
    RAISE NOTICE '⚠️  Necesitas crear el trigger manualmente (requiere permisos de OWNER)';
    RAISE NOTICE '⚠️  Consulta INSTRUCCIONES_CORREGIDAS_PERMISOS.md para más info';
  ELSE
    RAISE NOTICE '✅ El trigger on_auth_user_created EXISTE y está activo';
  END IF;
END $$;

-- ===================================================================
-- ✅ SCRIPT COMPLETADO
-- ===================================================================
-- SIGUIENTE PASO:
-- 1. Verifica los logs en: SELECT * FROM public.trigger_debug_log ORDER BY ts DESC LIMIT 20;
-- 2. Intenta crear un usuario nuevo
-- 3. Si falla, revisa los logs para ver exactamente dónde falló
-- ===================================================================
