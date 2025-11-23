-- ============================================================================
-- NUCLEAR FIX: EMAIL CONFIRMATION TRIGGER
-- ============================================================================
-- PROBLEMA: El trigger handle_email_confirmed está causando "Error confirming user"
-- SOLUCIÓN: Recrear trigger con manejo robusto de errores + logs detallados
-- FECHA: 2025-06-09
-- COMPATIBILIDAD: PostgREST/Supabase SQL Editor
-- ============================================================================

-- ============================================================================
-- PASO 1: CREAR TABLA DE LOGS (primero, para que trigger pueda usarla)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.function_logs (
  id BIGSERIAL PRIMARY KEY,
  function_name TEXT NOT NULL,
  message TEXT NOT NULL,
  metadata JSONB,
  level TEXT DEFAULT 'INFO',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Índice para búsquedas rápidas
CREATE INDEX IF NOT EXISTS idx_function_logs_function_name 
  ON public.function_logs(function_name, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_function_logs_level 
  ON public.function_logs(level, created_at DESC);

-- RLS: Solo admin puede ver logs
ALTER TABLE public.function_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS function_logs_admin_view ON public.function_logs;

CREATE POLICY function_logs_admin_view ON public.function_logs
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() 
      AND role = 'admin'
    )
  );

-- ============================================================================
-- PASO 2: DROP TRIGGER EXISTENTE
-- ============================================================================

DROP TRIGGER IF EXISTS on_auth_user_email_confirmed ON auth.users;

-- ============================================================================
-- PASO 3: CREAR FUNCIÓN CON MANEJO ROBUSTO DE ERRORES
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_email_confirmed()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  v_user_exists BOOLEAN;
  v_error_msg TEXT;
BEGIN
  -- Log inicial (solo si función log existe)
  BEGIN
    INSERT INTO public.function_logs (function_name, message, metadata)
    VALUES ('handle_email_confirmed', 'Trigger fired', jsonb_build_object(
      'user_id', NEW.id,
      'email', NEW.email,
      'old_confirmed_at', OLD.email_confirmed_at,
      'new_confirmed_at', NEW.email_confirmed_at
    ));
  EXCEPTION WHEN OTHERS THEN
    -- Ignorar si tabla de logs no existe
    NULL;
  END;

  -- Verificar si esto es una confirmación de email (NULL → timestamp)
  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN
    
    -- Verificar si el usuario existe en public.users
    SELECT EXISTS(
      SELECT 1 FROM public.users WHERE id = NEW.id
    ) INTO v_user_exists;
    
    IF v_user_exists THEN
      -- Usuario existe: actualizar email_confirm a true
      BEGIN
        UPDATE public.users
        SET 
          email_confirm = true,
          updated_at = now()
        WHERE id = NEW.id;
        
        -- Log éxito
        BEGIN
          INSERT INTO public.function_logs (function_name, message, metadata)
          VALUES ('handle_email_confirmed', 'Email confirmed successfully', jsonb_build_object(
            'user_id', NEW.id,
            'email', NEW.email
          ));
        EXCEPTION WHEN OTHERS THEN
          NULL;
        END;
        
      EXCEPTION WHEN OTHERS THEN
        -- CRÍTICO: NO LANZAR ERROR - solo loguear
        v_error_msg := SQLERRM;
        
        BEGIN
          INSERT INTO public.function_logs (function_name, message, metadata, level)
          VALUES ('handle_email_confirmed', 'ERROR updating users table', jsonb_build_object(
            'user_id', NEW.id,
            'email', NEW.email,
            'error', v_error_msg
          ), 'ERROR');
        EXCEPTION WHEN OTHERS THEN
          NULL;
        END;
        
        -- NO ROMPER LA TRANSACCIÓN - dejar que Supabase Auth complete
        -- RETURN NEW permite que el proceso continúe
      END;
    ELSE
      -- Usuario no existe en public.users - esto es extraño pero no fatal
      BEGIN
        INSERT INTO public.function_logs (function_name, message, metadata, level)
        VALUES ('handle_email_confirmed', 'WARNING: user not found in public.users', jsonb_build_object(
          'user_id', NEW.id,
          'email', NEW.email
        ), 'WARNING');
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END IF;
  END IF;
  
  -- SIEMPRE retornar NEW para no interrumpir el proceso
  RETURN NEW;
  
EXCEPTION WHEN OTHERS THEN
  -- CATCH-ALL: Loguear cualquier error inesperado pero NO FALLAR
  BEGIN
    INSERT INTO public.function_logs (function_name, message, metadata, level)
    VALUES ('handle_email_confirmed', 'CRITICAL ERROR in trigger', jsonb_build_object(
      'user_id', NEW.id,
      'email', NEW.email,
      'error', SQLERRM,
      'sqlstate', SQLSTATE
    ), 'CRITICAL');
  EXCEPTION WHEN OTHERS THEN
    -- Si hasta el log falla, no hacer nada
    NULL;
  END;
  
  -- SIEMPRE retornar NEW - NUNCA romper la confirmación de email
  RETURN NEW;
END;
$$;

-- ============================================================================
-- PASO 4: CREAR TRIGGER EN auth.users
-- ============================================================================

CREATE TRIGGER on_auth_user_email_confirmed
  AFTER UPDATE ON auth.users
  FOR EACH ROW
  WHEN (OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL)
  EXECUTE FUNCTION public.handle_email_confirmed();

-- ============================================================================
-- PASO 5: GRANT PERMISOS
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.handle_email_confirmed() TO service_role;
GRANT EXECUTE ON FUNCTION public.handle_email_confirmed() TO authenticated;
GRANT EXECUTE ON FUNCTION public.handle_email_confirmed() TO anon;

-- ============================================================================
-- PASO 6: VERIFICACIÓN - VER ESTADO FINAL
-- ============================================================================

-- Ver trigger creado
SELECT 
  'Trigger Status' as check_type,
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  CASE tgenabled
    WHEN 'O' THEN 'Enabled'
    WHEN 'D' THEN 'Disabled'
    ELSE 'Unknown'
  END as status
FROM pg_trigger
WHERE tgname = 'on_auth_user_email_confirmed';

-- Ver función creada
SELECT 
  'Function Status' as check_type,
  proname as function_name,
  prosecdef as is_security_definer
FROM pg_proc
WHERE proname = 'handle_email_confirmed'
  AND pronamespace = 'public'::regnamespace;

-- ============================================================================
-- RESUMEN FINAL
-- ============================================================================

SELECT '
╔═══════════════════════════════════════════════════════════════════╗
║                    ✅ MIGRACIÓN COMPLETADA                        ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  ✅ Tabla function_logs creada                                    ║
║  ✅ Trigger on_auth_user_email_confirmed recreado                 ║
║  ✅ Función handle_email_confirmed() con manejo robusto           ║
║  ✅ Permisos otorgados correctamente                              ║
║                                                                   ║
║  📋 VER LOGS:                                                     ║
║     SELECT * FROM function_logs ORDER BY created_at DESC LIMIT 20║
║                                                                   ║
║  🧪 PRUEBA AHORA:                                                 ║
║     1. Crea un nuevo usuario desde Flutter                        ║
║     2. Haz clic en el enlace de confirmación del email            ║
║     3. Ejecuta VIEW_EMAIL_CONFIRMATION_LOGS.sql para ver detalles ║
║                                                                   ║
║  ⚠️  IMPORTANTE:                                                  ║
║     Este trigger NUNCA romperá la confirmación de email           ║
║     Todos los errores se loguean pero no interrumpen el proceso   ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
' as resumen;
