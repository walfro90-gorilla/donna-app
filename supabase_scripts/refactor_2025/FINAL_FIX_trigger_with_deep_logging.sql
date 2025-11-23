-- =====================================================================
-- FINAL FIX: Corrección quirúrgica con LOGS PROFUNDOS
-- =====================================================================
-- Este script corrige el trigger que falla y agrega logs detallados
-- para rastrear exactamente qué está pasando durante el registro.
-- =====================================================================

-- ====================================
-- PASO 1: ASEGURAR TABLA DE DEBUG
-- ====================================
-- Esta tabla almacenará todos los logs del proceso de registro
-- ====================================
CREATE TABLE IF NOT EXISTS public.debug_trigger_logs (
  id bigserial PRIMARY KEY,
  ts timestamptz DEFAULT now(),
  trigger_name text NOT NULL,
  step_name text NOT NULL,
  user_id uuid,
  user_email text,
  status text NOT NULL, -- 'INFO', 'SUCCESS', 'ERROR', 'WARNING'
  message text NOT NULL,
  details jsonb DEFAULT '{}'::jsonb
);

-- Función helper para logging (no lanza errores)
CREATE OR REPLACE FUNCTION public.log_trigger_event(
  p_trigger_name text,
  p_step_name text,
  p_user_id uuid,
  p_user_email text,
  p_status text,
  p_message text,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.debug_trigger_logs (
    trigger_name,
    step_name,
    user_id,
    user_email,
    status,
    message,
    details
  ) VALUES (
    p_trigger_name,
    p_step_name,
    p_user_id,
    p_user_email,
    p_status,
    p_message,
    p_details
  );
EXCEPTION WHEN OTHERS THEN
  -- Si falla el log, no hacer nada (no queremos que el log rompa el registro)
  NULL;
END;
$$;

-- ====================================
-- PASO 2: FUNCIÓN CORREGIDA ensure_client_profile_and_account
-- ====================================
-- Usa SOLO las columnas que existen en DATABASE_SCHEMA.sql
-- ====================================
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
  v_user_email text;
  v_user_name text;
  v_user_phone text;
  v_result jsonb;
BEGIN
  -- LOG: Inicio del proceso
  SELECT email, 
         raw_user_meta_data->>'name',
         raw_user_meta_data->>'phone'
  INTO v_user_email, v_user_name, v_user_phone
  FROM auth.users 
  WHERE id = p_user_id;
  
  PERFORM log_trigger_event(
    'ensure_client_profile',
    '01_START',
    p_user_id,
    v_user_email,
    'INFO',
    'Iniciando creacion de perfil de cliente',
    jsonb_build_object(
      'user_email', v_user_email,
      'user_name', v_user_name,
      'user_phone', v_user_phone
    )
  );

  -- 1) Validar que el usuario existe en auth.users
  IF v_user_email IS NULL THEN
    PERFORM log_trigger_event(
      'ensure_client_profile',
      '02_VALIDATION_ERROR',
      p_user_id,
      NULL,
      'ERROR',
      'Usuario no encontrado en auth.users',
      jsonb_build_object('user_id', p_user_id)
    );
    RAISE EXCEPTION 'User % not found in auth.users', p_user_id;
  END IF;

  -- 2) Verificar si el usuario ya existe en public.users
  SELECT role INTO v_current_role
  FROM public.users 
  WHERE id = p_user_id;
  
  v_user_exists := (v_current_role IS NOT NULL);

  PERFORM log_trigger_event(
    'ensure_client_profile',
    '03_CHECK_EXISTING_USER',
    p_user_id,
    v_user_email,
    'INFO',
    'Verificando usuario existente',
    jsonb_build_object(
      'user_exists', v_user_exists,
      'current_role', v_current_role
    )
  );

  -- 3) SOLO crear perfil de cliente si no tiene un role especializado
  IF v_current_role IS NOT NULL AND v_current_role NOT IN ('', 'cliente', 'client') THEN
    PERFORM log_trigger_event(
      'ensure_client_profile',
      '04_SKIP_SPECIALIZED_ROLE',
      p_user_id,
      v_user_email,
      'INFO',
      'Usuario tiene role especializado, saltando creacion de perfil cliente',
      jsonb_build_object('role', v_current_role)
    );
    
    RETURN jsonb_build_object(
      'success', true, 
      'account_id', NULL, 
      'skipped', true, 
      'reason', 'specialized_role'
    );
  END IF;

  -- 4) Crear/actualizar usuario en public.users con role='cliente'
  IF NOT v_user_exists THEN
    PERFORM log_trigger_event(
      'ensure_client_profile',
      '05_CREATE_PUBLIC_USER',
      p_user_id,
      v_user_email,
      'INFO',
      'Creando usuario en public.users',
      jsonb_build_object(
        'email', v_user_email,
        'name', v_user_name,
        'phone', v_user_phone,
        'role', 'cliente'
      )
    );

    INSERT INTO public.users (
      id, 
      email, 
      name, 
      phone, 
      role, 
      email_confirm, 
      created_at, 
      updated_at
    )
    VALUES (
      p_user_id, 
      v_user_email, 
      v_user_name, 
      v_user_phone, 
      'cliente', 
      false, 
      v_now, 
      v_now
    )
    ON CONFLICT (id) DO NOTHING;
  ELSE
    -- Solo normalizar a 'cliente' si actualmente es vacío/cliente
    IF COALESCE(v_current_role, '') IN ('', 'cliente', 'client') THEN
      PERFORM log_trigger_event(
        'ensure_client_profile',
        '06_UPDATE_PUBLIC_USER',
        p_user_id,
        v_user_email,
        'INFO',
        'Actualizando usuario en public.users',
        jsonb_build_object('old_role', v_current_role, 'new_role', 'cliente')
      );
      
      UPDATE public.users 
      SET 
        role = 'cliente',
        email = COALESCE(email, v_user_email),
        name = COALESCE(name, v_user_name),
        phone = COALESCE(phone, v_user_phone),
        updated_at = v_now 
      WHERE id = p_user_id;
    END IF;
  END IF;

  -- 5) Asegurar perfil de cliente
  -- ⚠️ CRÍTICO: Usar SOLO columnas que existen en DATABASE_SCHEMA.sql
  -- ❌ NO incluir 'status' porque NO existe en client_profiles
  PERFORM log_trigger_event(
    'ensure_client_profile',
    '07_CREATE_CLIENT_PROFILE',
    p_user_id,
    v_user_email,
    'INFO',
    'Creando perfil en client_profiles',
    jsonb_build_object('user_id', p_user_id)
  );

  BEGIN
    INSERT INTO public.client_profiles (
      user_id, 
      created_at, 
      updated_at
      -- ✅ NO incluimos 'status', 'address', 'lat', 'lon', etc.
      -- porque se crean como NULL por defecto
    )
    VALUES (
      p_user_id, 
      v_now, 
      v_now
    )
    ON CONFLICT (user_id) DO UPDATE
      SET updated_at = EXCLUDED.updated_at;

    PERFORM log_trigger_event(
      'ensure_client_profile',
      '08_CLIENT_PROFILE_SUCCESS',
      p_user_id,
      v_user_email,
      'SUCCESS',
      'Perfil de cliente creado exitosamente',
      '{}'::jsonb
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM log_trigger_event(
      'ensure_client_profile',
      '08_CLIENT_PROFILE_ERROR',
      p_user_id,
      v_user_email,
      'ERROR',
      'Error al crear perfil de cliente',
      jsonb_build_object(
        'error_message', SQLERRM,
        'error_state', SQLSTATE
      )
    );
    RAISE;
  END;

  -- 6) Asegurar cuenta financiera tipo 'client' con balance 0
  SELECT id INTO v_account_id
  FROM public.accounts
  WHERE user_id = p_user_id AND account_type = 'client'
  LIMIT 1;
  
  IF v_account_id IS NULL THEN
    PERFORM log_trigger_event(
      'ensure_client_profile',
      '09_CREATE_ACCOUNT',
      p_user_id,
      v_user_email,
      'INFO',
      'Creando cuenta financiera',
      jsonb_build_object('account_type', 'client')
    );

    BEGIN
      INSERT INTO public.accounts (
        user_id, 
        account_type, 
        balance, 
        created_at, 
        updated_at
      )
      VALUES (
        p_user_id, 
        'client', 
        0.0, 
        v_now, 
        v_now
      )
      RETURNING id INTO v_account_id;

      PERFORM log_trigger_event(
        'ensure_client_profile',
        '10_ACCOUNT_SUCCESS',
        p_user_id,
        v_user_email,
        'SUCCESS',
        'Cuenta financiera creada exitosamente',
        jsonb_build_object('account_id', v_account_id)
      );
    EXCEPTION WHEN OTHERS THEN
      PERFORM log_trigger_event(
        'ensure_client_profile',
        '10_ACCOUNT_ERROR',
        p_user_id,
        v_user_email,
        'ERROR',
        'Error al crear cuenta financiera',
        jsonb_build_object(
          'error_message', SQLERRM,
          'error_state', SQLSTATE
        )
      );
      RAISE;
    END;
  ELSE
    PERFORM log_trigger_event(
      'ensure_client_profile',
      '10_ACCOUNT_EXISTS',
      p_user_id,
      v_user_email,
      'INFO',
      'Cuenta financiera ya existe',
      jsonb_build_object('account_id', v_account_id)
    );
  END IF;

  -- 7) Asegurar preferencias de usuario (defaults)
  PERFORM log_trigger_event(
    'ensure_client_profile',
    '11_CREATE_PREFERENCES',
    p_user_id,
    v_user_email,
    'INFO',
    'Creando preferencias de usuario',
    '{}'::jsonb
  );

  BEGIN
    INSERT INTO public.user_preferences (
      user_id, 
      has_seen_onboarding, 
      created_at, 
      updated_at
    )
    VALUES (
      p_user_id, 
      false, 
      v_now, 
      v_now
    )
    ON CONFLICT (user_id) DO NOTHING;

    PERFORM log_trigger_event(
      'ensure_client_profile',
      '12_PREFERENCES_SUCCESS',
      p_user_id,
      v_user_email,
      'SUCCESS',
      'Preferencias de usuario creadas exitosamente',
      '{}'::jsonb
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM log_trigger_event(
      'ensure_client_profile',
      '12_PREFERENCES_ERROR',
      p_user_id,
      v_user_email,
      'ERROR',
      'Error al crear preferencias',
      jsonb_build_object(
        'error_message', SQLERRM,
        'error_state', SQLSTATE
      )
    );
    -- No lanzar error aquí, preferencias no son críticas
  END;

  -- 8) Retornar éxito
  v_result := jsonb_build_object(
    'success', true, 
    'account_id', v_account_id,
    'user_role', 'cliente'
  );

  PERFORM log_trigger_event(
    'ensure_client_profile',
    '13_COMPLETE',
    p_user_id,
    v_user_email,
    'SUCCESS',
    'Proceso completado exitosamente',
    v_result
  );

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  PERFORM log_trigger_event(
    'ensure_client_profile',
    '99_FATAL_ERROR',
    p_user_id,
    COALESCE(v_user_email, 'UNKNOWN'),
    'ERROR',
    'Error fatal en ensure_client_profile_and_account',
    jsonb_build_object(
      'error_message', SQLERRM,
      'error_state', SQLSTATE,
      'error_detail', COALESCE(CURRENT_SETTING('last_error_context', true), 'N/A')
    )
  );
  RAISE;
END;
$$;

-- ====================================
-- PASO 3: FUNCIÓN CORREGIDA handle_new_user
-- ====================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM log_trigger_event(
    'handle_new_user',
    '01_TRIGGER_START',
    NEW.id,
    NEW.email,
    'INFO',
    'Trigger handle_new_user disparado',
    jsonb_build_object(
      'auth_user_id', NEW.id,
      'email', NEW.email,
      'confirmed_at', NEW.confirmed_at,
      'created_at', NEW.created_at
    )
  );

  -- Llamar a la función corregida
  SELECT public.ensure_client_profile_and_account(NEW.id) INTO v_result;
  
  PERFORM log_trigger_event(
    'handle_new_user',
    '02_TRIGGER_SUCCESS',
    NEW.id,
    NEW.email,
    'SUCCESS',
    'Trigger handle_new_user completado exitosamente',
    v_result
  );
  
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  PERFORM log_trigger_event(
    'handle_new_user',
    '99_TRIGGER_ERROR',
    NEW.id,
    NEW.email,
    'ERROR',
    'Error en trigger handle_new_user',
    jsonb_build_object(
      'error_message', SQLERRM,
      'error_state', SQLSTATE
    )
  );
  
  -- Re-lanzar el error para que falle el signup
  RAISE;
END;
$$;

-- ====================================
-- PASO 4: RECREAR TRIGGER
-- ====================================
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS trg_handle_new_user_on_auth_users ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ====================================
-- VERIFICACIÓN
-- ====================================
SELECT 
  '[OK] Trigger corregido y logs activados' as status;

-- Ver triggers existentes
SELECT 
  trigger_name,
  event_manipulation,
  event_object_table,
  action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'auth'
  AND event_object_table = 'users'
ORDER BY trigger_name;

-- ====================================
-- INSTRUCCIONES DE USO
-- ====================================
SELECT 
  '[INSTRUCCIONES] Como ver los logs' as titulo,
  '
  1. Ejecuta este script completo en el SQL Editor de Supabase
  
  2. Intenta crear un nuevo usuario desde la app
  
  3. Para ver los logs COMPLETOS del proceso, ejecuta:
  
     SELECT 
       to_char(ts, ''HH24:MI:SS.MS'') as tiempo,
       trigger_name,
       step_name,
       status,
       message,
       user_email,
       details
     FROM public.debug_trigger_logs
     WHERE user_email = ''TU_EMAIL@ejemplo.com''  -- reemplaza con el email que usaste
     ORDER BY ts DESC;
  
  4. Para ver SOLO los errores:
  
     SELECT 
       to_char(ts, ''HH24:MI:SS.MS'') as tiempo,
       step_name,
       message,
       details
     FROM public.debug_trigger_logs
     WHERE status = ''ERROR''
     ORDER BY ts DESC
     LIMIT 10;
  
  5. Para ver el ÚLTIMO intento de registro:
  
     SELECT 
       step_name,
       status,
       message,
       details
     FROM public.debug_trigger_logs
     ORDER BY ts DESC
     LIMIT 20;
  
  6. Si funciona correctamente, verás logs como:
     - 01_START → INFO
     - 03_CHECK_EXISTING_USER → INFO
     - 05_CREATE_PUBLIC_USER → INFO
     - 08_CLIENT_PROFILE_SUCCESS → SUCCESS
     - 10_ACCOUNT_SUCCESS → SUCCESS
     - 13_COMPLETE → SUCCESS
     - 02_TRIGGER_SUCCESS → SUCCESS
  
  7. Si falla, verás el paso exacto donde ocurrio el error.
  
  8. Una vez que funcione, puedes limpiar los logs con:
     TRUNCATE TABLE public.debug_trigger_logs;
  ' as instrucciones;
