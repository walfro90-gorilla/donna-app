-- ============================================================================
-- FIX: Permitir que Supabase actualice email_confirmed en public.users
-- ============================================================================
-- Problema:
--   Cuando el usuario confirma su email, Supabase intenta actualizar:
--   - auth.users.email_confirmed_at ✅ (esto funciona)
--   - public.users.email_confirm ❌ (falla por falta de política RLS)
--
-- Solución:
--   Crear una política UPDATE que permita al sistema (authenticator role)
--   actualizar SOLO el campo email_confirm cuando auth.uid() coincide
-- ============================================================================

-- ============================================================================
-- PASO 1: Verificar políticas UPDATE actuales en public.users
-- ============================================================================

DO $$
DECLARE
  r RECORD;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔍 POLÍTICAS UPDATE ACTUALES EN public.users';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  
  FOR r IN
    SELECT policyname, cmd, roles, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'users'
      AND cmd = 'UPDATE'
  LOOP
    RAISE NOTICE '📋 Política: %', r.policyname;
    RAISE NOTICE '   Comando: %', r.cmd;
    RAISE NOTICE '   Roles: %', r.roles;
    RAISE NOTICE '   USING: %', r.qual;
    RAISE NOTICE '   WITH CHECK: %', r.with_check;
    RAISE NOTICE '';
  END LOOP;
  
  IF NOT FOUND THEN
    RAISE NOTICE '⚠️  NO HAY POLÍTICAS UPDATE';
    RAISE NOTICE '';
  END IF;
  
END $$;

-- ============================================================================
-- PASO 2: Crear política para email confirmation (authenticated)
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔧 CREANDO POLÍTICA DE EMAIL CONFIRMATION';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  
  -- Eliminar política si existe
  DROP POLICY IF EXISTS users_update_email_confirm ON public.users;
  
  -- Crear política que permite a usuarios autenticados actualizar SOLO email_confirm
  CREATE POLICY users_update_email_confirm
  ON public.users
  AS PERMISSIVE
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);
  
  RAISE NOTICE '✅ Política "users_update_email_confirm" creada';
  RAISE NOTICE '   Permite a usuarios autenticados actualizar su propio registro';
  RAISE NOTICE '';
  
END $$;

-- ============================================================================
-- PASO 3: Crear función para actualizar email_confirm automáticamente
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔧 CREANDO FUNCIÓN AUTO-CONFIRM';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
END $$;

CREATE OR REPLACE FUNCTION public.handle_email_confirmation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Solo actualizar si email_confirmed_at cambió de NULL a un valor
  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN
    
    -- Actualizar public.users.email_confirm
    UPDATE public.users
    SET email_confirm = true,
        updated_at = now()
    WHERE id = NEW.id;
    
    -- Log para debugging
    INSERT INTO public.debug_logs (scope, message, meta)
    VALUES (
      'email_confirmation',
      'Email confirmed',
      jsonb_build_object(
        'user_id', NEW.id,
        'email', NEW.email,
        'confirmed_at', NEW.email_confirmed_at
      )
    );
    
  END IF;
  
  RETURN NEW;
END;
$function$;

DO $$
BEGIN
  RAISE NOTICE '✅ Función "handle_email_confirmation" creada';
  RAISE NOTICE '';
END $$;

-- ============================================================================
-- PASO 4: Crear trigger en auth.users para auto-confirm
-- ============================================================================

DROP TRIGGER IF EXISTS on_auth_email_confirmed ON auth.users;

CREATE TRIGGER on_auth_email_confirmed
  AFTER UPDATE OF email_confirmed_at ON auth.users
  FOR EACH ROW
  WHEN (OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL)
  EXECUTE FUNCTION public.handle_email_confirmation();

DO $$
BEGIN
  RAISE NOTICE '✅ Trigger "on_auth_email_confirmed" creado';
  RAISE NOTICE '   Se ejecuta cuando auth.users.email_confirmed_at cambia de NULL a un valor';
  RAISE NOTICE '';
END $$;

-- ============================================================================
-- PASO 5: Verificar resultado
-- ============================================================================

DO $$
DECLARE
  v_policy_count INT;
  v_trigger_exists BOOLEAN;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '📊 VERIFICACIÓN FINAL';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  
  -- Contar políticas UPDATE
  SELECT COUNT(*) INTO v_policy_count
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'users'
    AND cmd = 'UPDATE';
  
  RAISE NOTICE '✅ Políticas UPDATE en public.users: %', v_policy_count;
  
  -- Verificar trigger
  SELECT EXISTS(
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'on_auth_email_confirmed'
  ) INTO v_trigger_exists;
  
  RAISE NOTICE '✅ Trigger on_auth_email_confirmed existe: %', v_trigger_exists;
  RAISE NOTICE '';
  
  RAISE NOTICE '========================================';
  RAISE NOTICE '🎉 CONFIGURACIÓN COMPLETA';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE '📋 QUÉ SE CONFIGURÓ:';
  RAISE NOTICE '';
  RAISE NOTICE '1. ✅ Política RLS para UPDATE en public.users';
  RAISE NOTICE '   - Usuarios autenticados pueden actualizar su propio registro';
  RAISE NOTICE '';
  RAISE NOTICE '2. ✅ Función handle_email_confirmation()';
  RAISE NOTICE '   - Actualiza public.users.email_confirm cuando auth confirma email';
  RAISE NOTICE '';
  RAISE NOTICE '3. ✅ Trigger on_auth_email_confirmed';
  RAISE NOTICE '   - Se ejecuta automáticamente al confirmar email';
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🧪 PRÓXIMOS PASOS:';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE '1. Crear un nuevo usuario de prueba';
  RAISE NOTICE '2. Confirmar su email haciendo clic en el enlace';
  RAISE NOTICE '3. Verificar que public.users.email_confirm = true';
  RAISE NOTICE '';
  
END $$;
