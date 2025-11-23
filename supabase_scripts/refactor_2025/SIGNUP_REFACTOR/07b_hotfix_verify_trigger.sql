-- ============================================================================
-- HOTFIX 07b: VERIFICAR Y RECREAR TRIGGER
-- ============================================================================
-- Descripción: Fuerza la recreación del trigger y verifica que la función
--              master_handle_signup() esté usando la versión correcta
--              (normalizando roles a español: cliente/restaurante/repartidor)
-- ============================================================================

-- ============================================================================
-- PASO 1: Verificar la función actual
-- ============================================================================

DO $$
DECLARE
  v_function_body TEXT;
  v_has_client_normalization BOOLEAN := false;
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔍 VERIFICANDO FUNCIÓN master_handle_signup()';
  RAISE NOTICE '========================================';
  
  -- Obtener el cuerpo de la función
  SELECT pg_get_functiondef(oid) INTO v_function_body
  FROM pg_proc
  WHERE proname = 'master_handle_signup'
    AND pronamespace = 'public'::regnamespace;
  
  -- Verificar que tenga la normalización correcta
  v_has_client_normalization := v_function_body LIKE '%WHEN ''client'' THEN ''cliente''%';
  
  IF v_has_client_normalization THEN
    RAISE NOTICE '✅ La función tiene la normalización correcta (client -> cliente)';
  ELSE
    RAISE EXCEPTION '❌ La función NO tiene la normalización correcta. Ejecuta primero 04b_hotfix_master_function.sql';
  END IF;
  
END $$;

-- ============================================================================
-- PASO 2: Forzar recreación del trigger
-- ============================================================================

-- Eliminar trigger existente
DROP TRIGGER IF EXISTS master_handle_new_user ON auth.users;

-- Crear trigger de nuevo
CREATE TRIGGER master_handle_new_user
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.master_handle_signup();

-- ============================================================================
-- PASO 3: Limpiar datos de prueba anteriores fallidos
-- ============================================================================

DO $$
DECLARE
  v_deleted_users INT;
  v_deleted_auth_users INT;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '🧹 Limpiando datos de prueba anteriores...';
  
  -- Eliminar de auth.users (esto cascadea a public.users por el trigger)
  WITH deleted AS (
    DELETE FROM auth.users 
    WHERE email LIKE 'test_%@test.com'
    RETURNING id
  )
  SELECT COUNT(*) INTO v_deleted_auth_users FROM deleted;
  
  -- Por si acaso, limpiar manualmente public.users también
  WITH deleted AS (
    DELETE FROM public.users 
    WHERE email LIKE 'test_%@test.com'
    RETURNING id
  )
  SELECT COUNT(*) INTO v_deleted_users FROM deleted;
  
  RAISE NOTICE '   Eliminados % usuarios de auth.users', v_deleted_auth_users;
  RAISE NOTICE '   Eliminados % usuarios de public.users', v_deleted_users;
  RAISE NOTICE '✅ Limpieza completada';
  RAISE NOTICE '';
  RAISE NOTICE '🔧 Trigger master_handle_new_user recreado exitosamente';
  
END $$;

-- ============================================================================
-- PASO 4: Test simple de cliente
-- ============================================================================

DO $$
DECLARE
  v_test_email TEXT := 'test_simple_client_' || extract(epoch from now())::bigint || '@test.com';
  v_auth_id UUID := uuid_generate_v4();
  v_user_role TEXT;
  v_profile_exists BOOLEAN;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🧪 TEST SIMPLE: Signup de cliente';
  RAISE NOTICE '========================================';
  RAISE NOTICE '📧 Email: %', v_test_email;
  RAISE NOTICE '🆔 UUID: %', v_auth_id;
  RAISE NOTICE '';
  
  -- Simular signup
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
    jsonb_build_object('role', 'cliente', 'name', 'Test Simple Cliente'),
    now(), 
    now(),
    'authenticated',
    'authenticated',
    crypt('test_password_123', gen_salt('bf'))
  );
  
  -- Esperar un momento para que el trigger termine
  PERFORM pg_sleep(0.5);
  
  -- Verificar que se creó correctamente
  SELECT role INTO v_user_role
  FROM public.users 
  WHERE id = v_auth_id;
  
  SELECT EXISTS(
    SELECT 1 FROM public.client_profiles 
    WHERE user_id = v_auth_id
  ) INTO v_profile_exists;
  
  RAISE NOTICE '📊 RESULTADOS:';
  RAISE NOTICE '   public.users.role: %', COALESCE(v_user_role, 'NO EXISTE');
  RAISE NOTICE '   client_profiles exists: %', v_profile_exists;
  RAISE NOTICE '';
  
  IF v_user_role = 'cliente' AND v_profile_exists THEN
    RAISE NOTICE '✅ TEST SIMPLE PASADO';
    RAISE NOTICE '   El trigger está funcionando correctamente';
  ELSE
    RAISE EXCEPTION '❌ TEST SIMPLE FALLIDO: role=%, profile_exists=%', v_user_role, v_profile_exists;
  END IF;
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ TEST SIMPLE FALLIDO con error:';
    RAISE NOTICE '   %', SQLERRM;
    RAISE NOTICE '';
    RAISE NOTICE '📋 Ver logs de debug:';
    RAISE NOTICE 'SELECT * FROM debug_user_signup_log WHERE email = ''%'' ORDER BY created_at DESC;', v_test_email;
    RAISE;
END $$;

-- ============================================================================
-- RESUMEN
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ VERIFICACIÓN COMPLETADA';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE '🚀 Ahora puedes ejecutar el script 07 completo';
  RAISE NOTICE '   (07_validation_test_signup.sql)';
  RAISE NOTICE '';
END $$;
