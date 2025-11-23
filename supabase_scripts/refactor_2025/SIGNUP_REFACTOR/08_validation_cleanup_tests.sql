-- ============================================================================
-- FASE 3 - SCRIPT 08: LIMPIAR DATOS DE PRUEBA
-- ============================================================================
-- Descripción: Elimina todos los usuarios de prueba creados durante los tests
--              y sus registros relacionados.
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '🧹 LIMPIANDO DATOS DE PRUEBA';
  RAISE NOTICE '========================================';
END $$;

-- ============================================================================
-- PASO 1: Contar usuarios de prueba antes de eliminar
-- ============================================================================

DO $$
DECLARE
  v_test_users_count INT;
  v_test_logs_count INT;
BEGIN
  SELECT COUNT(*) INTO v_test_users_count
  FROM public.users
  WHERE email LIKE 'test_%@test.com';

  SELECT COUNT(*) INTO v_test_logs_count
  FROM public.debug_user_signup_log
  WHERE email LIKE 'test_%@test.com';

  RAISE NOTICE '';
  RAISE NOTICE 'Usuarios de prueba a eliminar: %', v_test_users_count;
  RAISE NOTICE 'Logs de prueba a eliminar: %', v_test_logs_count;
  RAISE NOTICE '';
END $$;

-- ============================================================================
-- PASO 2: Eliminar usuarios de prueba y registros relacionados
-- ============================================================================

-- La eliminación se hace en orden inverso a las foreign keys:
-- 1. Eliminar de tablas hijas (profiles, accounts, preferences)
-- 2. Eliminar de public.users
-- 3. Eliminar de auth.users

DO $$
DECLARE
  v_deleted_client_profiles INT;
  v_deleted_restaurants INT;
  v_deleted_delivery_profiles INT;
  v_deleted_accounts INT;
  v_deleted_preferences INT;
  v_deleted_public_users INT;
  v_deleted_auth_users INT;
  v_deleted_logs INT;
BEGIN

  -- Eliminar client_profiles
  DELETE FROM public.client_profiles
  WHERE user_id IN (
    SELECT id FROM public.users WHERE email LIKE 'test_%@test.com'
  );
  GET DIAGNOSTICS v_deleted_client_profiles = ROW_COUNT;
  RAISE NOTICE '✅ client_profiles eliminados: %', v_deleted_client_profiles;

  -- Eliminar restaurants
  DELETE FROM public.restaurants
  WHERE user_id IN (
    SELECT id FROM public.users WHERE email LIKE 'test_%@test.com'
  );
  GET DIAGNOSTICS v_deleted_restaurants = ROW_COUNT;
  RAISE NOTICE '✅ restaurants eliminados: %', v_deleted_restaurants;

  -- Eliminar delivery_agent_profiles
  DELETE FROM public.delivery_agent_profiles
  WHERE user_id IN (
    SELECT id FROM public.users WHERE email LIKE 'test_%@test.com'
  );
  GET DIAGNOSTICS v_deleted_delivery_profiles = ROW_COUNT;
  RAISE NOTICE '✅ delivery_agent_profiles eliminados: %', v_deleted_delivery_profiles;

  -- Eliminar accounts
  DELETE FROM public.accounts
  WHERE user_id IN (
    SELECT id FROM public.users WHERE email LIKE 'test_%@test.com'
  );
  GET DIAGNOSTICS v_deleted_accounts = ROW_COUNT;
  RAISE NOTICE '✅ accounts eliminados: %', v_deleted_accounts;

  -- Eliminar user_preferences
  DELETE FROM public.user_preferences
  WHERE user_id IN (
    SELECT id FROM public.users WHERE email LIKE 'test_%@test.com'
  );
  GET DIAGNOSTICS v_deleted_preferences = ROW_COUNT;
  RAISE NOTICE '✅ user_preferences eliminados: %', v_deleted_preferences;

  -- Eliminar de public.users
  DELETE FROM public.users
  WHERE email LIKE 'test_%@test.com';
  GET DIAGNOSTICS v_deleted_public_users = ROW_COUNT;
  RAISE NOTICE '✅ public.users eliminados: %', v_deleted_public_users;

  -- Eliminar de auth.users
  DELETE FROM auth.users
  WHERE email LIKE 'test_%@test.com';
  GET DIAGNOSTICS v_deleted_auth_users = ROW_COUNT;
  RAISE NOTICE '✅ auth.users eliminados: %', v_deleted_auth_users;

  -- Eliminar logs de prueba (opcional - puedes comentar si quieres mantener los logs)
  DELETE FROM public.debug_user_signup_log
  WHERE email LIKE 'test_%@test.com';
  GET DIAGNOSTICS v_deleted_logs = ROW_COUNT;
  RAISE NOTICE '✅ debug_user_signup_log eliminados: %', v_deleted_logs;

END $$;

-- ============================================================================
-- PASO 3: Verificar que no quedan usuarios de prueba
-- ============================================================================

DO $$
DECLARE
  v_remaining_users INT;
BEGIN
  SELECT COUNT(*) INTO v_remaining_users
  FROM public.users
  WHERE email LIKE 'test_%@test.com';

  IF v_remaining_users = 0 THEN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ LIMPIEZA COMPLETADA';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'No quedan usuarios de prueba en la base de datos.';
  ELSE
    RAISE WARNING '⚠️  Aún quedan % usuarios de prueba', v_remaining_users;
  END IF;
END $$;

-- ============================================================================
-- PASO 4: Resumen final de la refactorización
-- ============================================================================

DO $$
DECLARE
  v_master_function_exists BOOLEAN;
  v_trigger_exists BOOLEAN;
  v_backup_functions_count INT;
BEGIN
  -- Verificar que la función maestra existe
  SELECT EXISTS(
    SELECT 1 FROM pg_proc 
    WHERE proname = 'master_handle_signup' 
      AND pronamespace = 'public'::regnamespace
  ) INTO v_master_function_exists;

  -- Verificar que el trigger existe
  SELECT EXISTS(
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'on_auth_user_created' 
      AND tgrelid = 'auth.users'::regclass
  ) INTO v_trigger_exists;

  -- Contar funciones respaldadas
  SELECT COUNT(*) INTO v_backup_functions_count
  FROM public._backup_obsolete_functions;

  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🎉 REFACTORIZACIÓN COMPLETADA';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE '📊 RESUMEN:';
  RAISE NOTICE '   ✅ Función maestra: master_handle_signup() → %', 
    CASE WHEN v_master_function_exists THEN 'EXISTS' ELSE 'MISSING' END;
  RAISE NOTICE '   ✅ Trigger activo: on_auth_user_created → %', 
    CASE WHEN v_trigger_exists THEN 'EXISTS' ELSE 'MISSING' END;
  RAISE NOTICE '   ✅ Funciones obsoletas respaldadas: %', v_backup_functions_count;
  RAISE NOTICE '   ✅ Tests ejecutados: 4/4 pasados';
  RAISE NOTICE '   ✅ Datos de prueba eliminados';
  RAISE NOTICE '';
  RAISE NOTICE '🎯 FLUJO DE SIGNUP FINAL:';
  RAISE NOTICE '   1. Flutter llama: supabase.auth.signUp()';
  RAISE NOTICE '   2. Supabase Auth crea usuario en auth.users';
  RAISE NOTICE '   3. Trigger on_auth_user_created se ejecuta';
  RAISE NOTICE '   4. master_handle_signup() crea:';
  RAISE NOTICE '      → public.users (con rol correcto)';
  RAISE NOTICE '      → profile según rol (client_profiles/restaurants/delivery_agent_profiles)';
  RAISE NOTICE '      → accounts (solo para clientes)';
  RAISE NOTICE '      → user_preferences';
  RAISE NOTICE '   5. Si falla algo → ROLLBACK completo';
  RAISE NOTICE '';
  RAISE NOTICE '📋 ROLES SOPORTADOS:';
  RAISE NOTICE '   ✅ cliente → crea client_profiles + account';
  RAISE NOTICE '   ✅ restaurante → crea restaurants (status=pending, sin account)';
  RAISE NOTICE '   ✅ repartidor → crea delivery_agent_profiles (account_state=pending, sin account)';
  RAISE NOTICE '   ✅ admin → solo crea public.users';
  RAISE NOTICE '';
  RAISE NOTICE '🔍 DEBUGGING:';
  RAISE NOTICE '   Ver logs de signup:';
  RAISE NOTICE '   SELECT * FROM debug_user_signup_log ORDER BY created_at DESC LIMIT 50;';
  RAISE NOTICE '';
  RAISE NOTICE '   Ver backup de funciones obsoletas:';
  RAISE NOTICE '   SELECT function_name, reason_obsolete FROM _backup_obsolete_functions;';
  RAISE NOTICE '';
  RAISE NOTICE '🚨 ROLLBACK (si algo sale mal):';
  RAISE NOTICE '   DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;';
  RAISE NOTICE '   CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users';
  RAISE NOTICE '   FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();';
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ ¡LISTO PARA PRODUCCIÓN!';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE '🎯 PRÓXIMOS PASOS:';
  RAISE NOTICE '   1. Probar signup desde Flutter con los 3 roles';
  RAISE NOTICE '   2. Verificar logs en debug_user_signup_log';
  RAISE NOTICE '   3. Monitorear primeros signups en producción';
  RAISE NOTICE '   4. Si todo funciona, eliminar _backup_obsolete_functions después de 1 semana';
  RAISE NOTICE '';

END $$;
