-- ================================================================================
-- 🔧 FIX EMAIL CONFIRMATION - CONFIGURACIÓN COMPLETA
-- ================================================================================
-- Este script soluciona el problema "otp_expired" / "Email link is invalid or has expired"
-- 
-- PROBLEMA IDENTIFICADO:
-- - El token de confirmación expira antes de que el usuario haga clic
-- - El redirect URL no está correctamente configurado
-- - Hay usuarios desincronizados (confirmados en auth pero no en public)
--
-- SOLUCIONES:
-- 1. Sincronizar usuarios existentes desincronizados
-- 2. Verificar y mostrar configuración de email templates
-- 3. Crear función para reenviar confirmación con parámetros correctos
-- ================================================================================

DO $$
BEGIN
  RAISE NOTICE '🚀 ========== INICIANDO CORRECCIÓN COMPLETA DE EMAIL CONFIRMATION ==========';
END $$;

-- ================================================================================
-- 1️⃣ SINCRONIZAR USUARIOS DESINCRONIZADOS
-- ================================================================================

DO $$
DECLARE
  v_count INTEGER;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '1️⃣ ========== SINCRONIZANDO USUARIOS DESINCRONIZADOS ==========';
  
  -- Actualizar public.users donde auth.users ya tiene email_confirmed_at
  UPDATE public.users pu
  SET 
    email_confirm = true,
    updated_at = now()
  FROM auth.users au
  WHERE 
    pu.id = au.id 
    AND au.email_confirmed_at IS NOT NULL
    AND pu.email_confirm = false;
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE '✅ Sincronizados % usuarios', v_count;
END $$;

-- ================================================================================
-- 2️⃣ MOSTRAR CONFIGURACIÓN ACTUAL DE EMAIL TEMPLATES
-- ================================================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '2️⃣ ========== CONFIGURACIÓN DE EMAIL TEMPLATES (IMPORTANTE) ==========';
  RAISE NOTICE '';
  RAISE NOTICE '⚠️ DEBES VERIFICAR MANUALMENTE EN SUPABASE DASHBOARD:';
  RAISE NOTICE '';
  RAISE NOTICE '👉 Authentication > Email Templates > Confirm Signup';
  RAISE NOTICE '';
  RAISE NOTICE '✅ CONFIGURACIÓN CORRECTA:';
  RAISE NOTICE '   - Confirmation redirect URL: https://i20tpls7s2z0kjevuoyg.share.dreamflow.app/';
  RAISE NOTICE '   - Token expiration: 86400 seconds (24 horas)';
  RAISE NOTICE '   - Token hash: true (habilitado)';
  RAISE NOTICE '';
  RAISE NOTICE '📧 TEMPLATE DEBE CONTENER:';
  RAISE NOTICE '   {{ .ConfirmationURL }}  <-- Este debe apuntar al redirect URL correcto';
  RAISE NOTICE '';
  RAISE NOTICE '🔧 SI NO ESTÁ CONFIGURADO:';
  RAISE NOTICE '   1. Ve a: Authentication > URL Configuration';
  RAISE NOTICE '   2. Agrega Site URL: https://i20tpls7s2z0kjevuoyg.share.dreamflow.app';
  RAISE NOTICE '   3. Agrega Redirect URL: https://i20tpls7s2z0kjevuoyg.share.dreamflow.app/**';
  RAISE NOTICE '';
END $$;

-- ================================================================================
-- 3️⃣ CREAR FUNCIÓN PARA REENVIAR CONFIRMACIÓN DE EMAIL
-- ================================================================================

CREATE OR REPLACE FUNCTION public.resend_email_confirmation(
  p_user_email TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
  v_already_confirmed boolean;
  v_result jsonb;
BEGIN
  -- Buscar usuario por email
  SELECT id, email_confirmed_at IS NOT NULL
  INTO v_user_id, v_already_confirmed
  FROM auth.users
  WHERE email = p_user_email;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Usuario no encontrado',
      'email', p_user_email
    );
  END IF;

  IF v_already_confirmed THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Email ya confirmado',
      'user_id', v_user_id,
      'email', p_user_email
    );
  END IF;

  -- Nota: Esta función solo valida, el reenvío real lo hace Supabase Auth
  -- desde el cliente con: supabase.auth.resend({ type: 'signup', email: '...' })
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Listo para reenviar - usa supabase.auth.resend() desde cliente',
    'user_id', v_user_id,
    'email', p_user_email
  );
END;
$$;

COMMENT ON FUNCTION public.resend_email_confirmation IS 
'Valida si un usuario puede recibir reenvío de email de confirmación. El reenvío real debe hacerse desde cliente con supabase.auth.resend()';

-- ================================================================================
-- 4️⃣ VERIFICACIÓN FINAL
-- ================================================================================

DO $$
DECLARE
  v_total_users INTEGER;
  v_confirmed_auth INTEGER;
  v_confirmed_public INTEGER;
  v_pending_confirmation INTEGER;
  v_desincronizados INTEGER;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '4️⃣ ========== VERIFICACIÓN FINAL ==========';
  
  SELECT COUNT(*) INTO v_total_users FROM auth.users;
  
  SELECT COUNT(*) INTO v_confirmed_auth 
  FROM auth.users WHERE email_confirmed_at IS NOT NULL;
  
  SELECT COUNT(*) INTO v_confirmed_public 
  FROM public.users WHERE email_confirm = true;
  
  SELECT COUNT(*) INTO v_pending_confirmation
  FROM auth.users 
  WHERE email_confirmed_at IS NULL;
  
  SELECT COUNT(*) INTO v_desincronizados
  FROM auth.users au
  LEFT JOIN public.users pu ON pu.id = au.id
  WHERE au.email_confirmed_at IS NOT NULL 
    AND (pu.email_confirm = false OR pu.email_confirm IS NULL);
  
  RAISE NOTICE '';
  RAISE NOTICE '📊 ESTADÍSTICAS:';
  RAISE NOTICE '   Total usuarios: %', v_total_users;
  RAISE NOTICE '   Confirmados en auth.users: %', v_confirmed_auth;
  RAISE NOTICE '   Confirmados en public.users: %', v_confirmed_public;
  RAISE NOTICE '   Pendientes de confirmación: %', v_pending_confirmation;
  RAISE NOTICE '   ⚠️ Desincronizados (DEBE SER 0): %', v_desincronizados;
  RAISE NOTICE '';
  
  IF v_desincronizados = 0 THEN
    RAISE NOTICE '✅ Todos los usuarios están correctamente sincronizados';
  ELSE
    RAISE NOTICE '❌ ERROR: Hay % usuarios desincronizados - ejecutar script de nuevo', v_desincronizados;
  END IF;
END $$;

-- ================================================================================
-- 5️⃣ MOSTRAR INSTRUCCIONES FINALES
-- ================================================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '5️⃣ ========== INSTRUCCIONES FINALES ==========';
  RAISE NOTICE '';
  RAISE NOTICE '✅ SCRIPT COMPLETADO';
  RAISE NOTICE '';
  RAISE NOTICE '📋 SIGUIENTE PASO - VERIFICA EN SUPABASE DASHBOARD:';
  RAISE NOTICE '';
  RAISE NOTICE '1️⃣ Ve a: Authentication > URL Configuration';
  RAISE NOTICE '   ✓ Site URL: https://i20tpls7s2z0kjevuoyg.share.dreamflow.app';
  RAISE NOTICE '   ✓ Redirect URLs: https://i20tpls7s2z0kjevuoyg.share.dreamflow.app/**';
  RAISE NOTICE '';
  RAISE NOTICE '2️⃣ Ve a: Authentication > Email Templates > Confirm signup';
  RAISE NOTICE '   ✓ Verifica que {{ .ConfirmationURL }} esté presente';
  RAISE NOTICE '   ✓ Token expiration: 86400 (recomendado)';
  RAISE NOTICE '';
  RAISE NOTICE '3️⃣ PRUEBA CON NUEVO USUARIO:';
  RAISE NOTICE '   - Registra un nuevo usuario';
  RAISE NOTICE '   - Verifica que el email llegue';
  RAISE NOTICE '   - Copia el enlace y verifica que contenga:';
  RAISE NOTICE '     * token_hash=...';
  RAISE NOTICE '     * type=signup';
  RAISE NOTICE '     * redirect_to=https://i20tpls7s2z0kjevuoyg.share.dreamflow.app';
  RAISE NOTICE '';
  RAISE NOTICE '❗ SI EL TOKEN SIGUE EXPIRANDO:';
  RAISE NOTICE '   1. Revisa spam/junk del correo';
  RAISE NOTICE '   2. Verifica que estés haciendo clic INMEDIATAMENTE';
  RAISE NOTICE '   3. Verifica la fecha/hora del servidor vs tu timezone';
  RAISE NOTICE '   4. Considera aumentar token expiration a 604800 (7 días)';
  RAISE NOTICE '';
  RAISE NOTICE '🎯 SIGUIENTE DEBUG SI FALLA:';
  RAISE NOTICE '   Ejecuta: SELECT * FROM public.function_logs';
  RAISE NOTICE '   WHERE function_name = ''handle_email_confirmed''';
  RAISE NOTICE '   ORDER BY created_at DESC LIMIT 10;';
  RAISE NOTICE '';
  RAISE NOTICE '✨ ========== FIN DEL SCRIPT ==========';
END $$;
