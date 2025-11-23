-- ============================================================
-- SOLUCIÓN DEFINITIVA: EMAIL CONFIRMATION
-- Elimina triggers duplicados y crea UNO SOLO robusto
-- ============================================================

-- ============================================================
-- PARTE 1: VERIFICAR/CREAR TABLAS DE LOGS
-- ============================================================

-- Tabla de logs para triggers (basada en DATABASE_SCHEMA.sql líneas 357-367)
CREATE TABLE IF NOT EXISTS public.trigger_debug_log (
  id BIGSERIAL PRIMARY KEY,
  ts TIMESTAMPTZ DEFAULT now(),
  function_name TEXT NOT NULL,
  user_id UUID,
  event TEXT NOT NULL,
  details JSONB DEFAULT '{}'::jsonb,
  error_message TEXT,
  stack_trace TEXT
);

-- Tabla de logs para funciones (basada en DATABASE_SCHEMA.sql líneas 170-178)
CREATE TABLE IF NOT EXISTS public.function_logs (
  id BIGSERIAL PRIMARY KEY,
  function_name TEXT NOT NULL,
  message TEXT NOT NULL,
  metadata JSONB,
  level TEXT DEFAULT 'INFO'::text,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Habilitar RLS en ambas (pero permitir todo a authenticated)
ALTER TABLE public.trigger_debug_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.function_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS trigger_debug_log_all ON public.trigger_debug_log;
CREATE POLICY trigger_debug_log_all ON public.trigger_debug_log
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS function_logs_all ON public.function_logs;
CREATE POLICY function_logs_all ON public.function_logs
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ============================================================
-- PARTE 2: ELIMINAR TODOS LOS TRIGGERS DUPLICADOS
-- ============================================================

-- Eliminar triggers existentes (sin importar cuántos haya)
DROP TRIGGER IF EXISTS on_auth_email_confirmed ON auth.users;
DROP TRIGGER IF EXISTS on_auth_user_email_confirmed ON auth.users;
DROP TRIGGER IF EXISTS trg_handle_user_email_confirmation ON auth.users;

-- Eliminar funciones antiguas
DROP FUNCTION IF EXISTS public.handle_email_confirmation() CASCADE;
DROP FUNCTION IF EXISTS public.handle_email_confirmed() CASCADE;
DROP FUNCTION IF EXISTS public.handle_user_email_confirmation() CASCADE;

-- ============================================================
-- PARTE 3: CREAR LA FUNCIÓN DEFINITIVA (UNA SOLA)
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_email_confirmation_final()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_exists BOOLEAN;
  v_error_msg TEXT;
BEGIN
  -- Log inicial
  BEGIN
    INSERT INTO public.trigger_debug_log (
      function_name, event, user_id, details
    ) VALUES (
      'handle_email_confirmation_final',
      TG_OP,
      NEW.id,
      jsonb_build_object(
        'email', NEW.email,
        'old_confirmed_at', OLD.email_confirmed_at,
        'new_confirmed_at', NEW.email_confirmed_at,
        'is_confirmation', (OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL)
      )
    );
  EXCEPTION WHEN OTHERS THEN
    -- Si falla el log, continuar igual
    NULL;
  END;

  -- Verificar si esto es una confirmación de email (NULL → timestamp)
  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN
    
    -- Log: confirmación detectada
    BEGIN
      INSERT INTO public.trigger_debug_log (
        function_name, event, user_id, details
      ) VALUES (
        'handle_email_confirmation_final',
        'email_confirmation_detected',
        NEW.id,
        jsonb_build_object('email', NEW.email, 'message', 'Processing email confirmation')
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
    
    -- Verificar si el usuario existe en public.users
    SELECT EXISTS(
      SELECT 1 FROM public.users WHERE id = NEW.id
    ) INTO v_user_exists;
    
    IF v_user_exists THEN
      -- Usuario existe: actualizar email_confirm
      BEGIN
        UPDATE public.users
        SET 
          email_confirm = true,
          updated_at = now()
        WHERE id = NEW.id;
        
        -- Log éxito
        BEGIN
          INSERT INTO public.trigger_debug_log (
            function_name, event, user_id, details
          ) VALUES (
            'handle_email_confirmation_final',
            'success',
            NEW.id,
            jsonb_build_object('email', NEW.email, 'message', 'Email confirmed successfully in public.users')
          );
        EXCEPTION WHEN OTHERS THEN NULL; END;
        
      EXCEPTION WHEN OTHERS THEN
        v_error_msg := SQLERRM;
        
        -- Log error PERO NO FALLAR
        BEGIN
          INSERT INTO public.trigger_debug_log (
            function_name, event, user_id, details, error_message, stack_trace
          ) VALUES (
            'handle_email_confirmation_final',
            'error_updating_users',
            NEW.id,
            jsonb_build_object('email', NEW.email, 'sqlstate', SQLSTATE),
            v_error_msg,
            pg_catalog.pg_get_backend_pid()::text
          );
        EXCEPTION WHEN OTHERS THEN NULL; END;
        
        -- NO LANZAR ERROR - dejar que Supabase Auth complete
      END;
    ELSE
      -- Usuario no existe - raro pero no fatal
      BEGIN
        INSERT INTO public.trigger_debug_log (
          function_name, event, user_id, details, error_message
        ) VALUES (
          'handle_email_confirmation_final',
          'warning_user_not_found',
          NEW.id,
          jsonb_build_object('email', NEW.email),
          'User not found in public.users'
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
  ELSE
    -- No es una confirmación - skip
    BEGIN
      INSERT INTO public.trigger_debug_log (
        function_name, event, user_id, details
      ) VALUES (
        'handle_email_confirmation_final',
        'skipped_not_confirmation',
        NEW.id,
        jsonb_build_object(
          'email', NEW.email,
          'reason', 'no_transition',
          'old_confirmed_at', OLD.email_confirmed_at,
          'new_confirmed_at', NEW.email_confirmed_at
        )
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  
  -- SIEMPRE retornar NEW para no interrumpir Supabase Auth
  RETURN NEW;
  
EXCEPTION WHEN OTHERS THEN
  -- CATCH-ALL: Loguear error crítico pero NO FALLAR
  BEGIN
    INSERT INTO public.trigger_debug_log (
      function_name, event, user_id, details, error_message, stack_trace
    ) VALUES (
      'handle_email_confirmation_final',
      'critical_error',
      NEW.id,
      jsonb_build_object('email', NEW.email, 'sqlstate', SQLSTATE),
      SQLERRM,
      pg_catalog.pg_get_backend_pid()::text
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;
  
  -- SIEMPRE retornar NEW - NUNCA romper la confirmación
  RETURN NEW;
END;
$$;

-- ============================================================
-- PARTE 4: CREAR EL TRIGGER DEFINITIVO (UNO SOLO)
-- ============================================================

CREATE TRIGGER trg_email_confirmation_final
  AFTER UPDATE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_email_confirmation_final();

-- ============================================================
-- PARTE 5: SINCRONIZAR USUARIOS EXISTENTES SIN CONFIRMAR
-- ============================================================

-- Sincronizar usuarios que están confirmados en auth.users pero no en public.users
UPDATE public.users u
SET 
  email_confirm = true,
  updated_at = now()
FROM auth.users au
WHERE u.id = au.id
  AND au.email_confirmed_at IS NOT NULL
  AND u.email_confirm = false;

-- ============================================================
-- PARTE 6: VERIFICACIÓN FINAL
-- ============================================================

-- Mostrar estado final
SELECT 
  '✅ SCRIPT COMPLETADO - VERIFICACIÓN:' as status;

-- Mostrar triggers activos en auth.users
SELECT 
  'TRIGGERS ACTIVOS' as seccion,
  tgname as trigger_name,
  pg_get_triggerdef(oid) as definition
FROM pg_trigger
WHERE tgrelid = 'auth.users'::regclass
  AND tgname LIKE '%email%'
ORDER BY tgname;

-- Mostrar usuarios sin confirmar
SELECT 
  'USUARIOS SIN CONFIRMAR' as seccion,
  u.id,
  u.email,
  u.name,
  u.email_confirm as public_confirmed,
  au.email_confirmed_at as auth_confirmed_at
FROM public.users u
LEFT JOIN auth.users au ON u.id = au.id
WHERE u.email_confirm = false
ORDER BY u.created_at DESC
LIMIT 5;

-- Mostrar últimos logs del trigger (si hay)
SELECT 
  'ÚLTIMOS LOGS DEL TRIGGER' as seccion,
  ts,
  function_name,
  event,
  user_id,
  details,
  error_message,
  stack_trace
FROM public.trigger_debug_log
ORDER BY ts DESC
LIMIT 10;
