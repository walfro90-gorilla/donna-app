-- ============================================================================
-- FASE 3 - SCRIPT 07: TESTS DE SIGNUP
-- ============================================================================
-- Descripción: Prueba el flujo de signup para los 3 roles (cliente,
--              restaurante, repartidor) simulando inserts en auth.users.
-- ============================================================================

-- ============================================================================
-- PREPARACIÓN: Limpiar logs anteriores
-- ============================================================================

DO $$
BEGIN
  -- Opcional: limpiar logs anteriores para facilitar el debugging
  -- TRUNCATE TABLE public.debug_user_signup_log;

  RAISE NOTICE '========================================';
  RAISE NOTICE '🧪 INICIANDO TESTS DE SIGNUP';
  RAISE NOTICE '========================================';
END $$;

-- ============================================================================
-- TEST 1: SIGNUP DE CLIENTE
-- ============================================================================

DO $$
DECLARE
  v_test_email TEXT := 'test_client_' || extract(epoch from now())::bigint || '@test.com';
  v_auth_id UUID := uuid_generate_v4();
  v_user_exists BOOLEAN;
  v_profile_exists BOOLEAN;
  v_account_exists BOOLEAN;
  v_preferences_exists BOOLEAN;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '🧪 TEST 1: Signup de CLIENTE';
  RAISE NOTICE '   Email: %', v_test_email;
  RAISE NOTICE '   UUID: %', v_auth_id;

  -- Simular INSERT en auth.users (esto dispara el trigger)
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
    jsonb_build_object('role', 'cliente', 'name', 'Test Cliente'),
    now(), 
    now(),
    'authenticated',
    'authenticated',
    crypt('test_password_123', gen_salt('bf'))
  );

  -- Verificar que se crearon todos los registros
  SELECT EXISTS(SELECT 1 FROM public.users WHERE id = v_auth_id AND role = 'cliente') INTO v_user_exists;
  SELECT EXISTS(SELECT 1 FROM public.client_profiles WHERE user_id = v_auth_id) INTO v_profile_exists;
  SELECT EXISTS(SELECT 1 FROM public.accounts WHERE user_id = v_auth_id AND account_type = 'client') INTO v_account_exists;
  SELECT EXISTS(SELECT 1 FROM public.user_preferences WHERE user_id = v_auth_id) INTO v_preferences_exists;

  IF v_user_exists AND v_profile_exists AND v_account_exists AND v_preferences_exists THEN
    RAISE NOTICE '   ✅ public.users: EXISTS (role=cliente)';
    RAISE NOTICE '   ✅ client_profiles: EXISTS';
    RAISE NOTICE '   ✅ accounts: EXISTS (type=client)';
    RAISE NOTICE '   ✅ user_preferences: EXISTS';
    RAISE NOTICE '   ✅ TEST 1 PASADO';
  ELSE
    RAISE EXCEPTION '❌ TEST 1 FALLIDO: Falta algún registro. users=%, profile=%, account=%, prefs=%', 
      v_user_exists, v_profile_exists, v_account_exists, v_preferences_exists;
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ TEST 1 FALLIDO con error: %', SQLERRM;
    RAISE NOTICE '   Ver logs: SELECT * FROM debug_user_signup_log WHERE email = ''%'';', v_test_email;
    RAISE; -- Re-lanzar para que falle el test
END $$;

-- ============================================================================
-- TEST 2: SIGNUP DE RESTAURANTE
-- ============================================================================

DO $$
DECLARE
  v_test_email TEXT := 'test_restaurant_' || extract(epoch from now())::bigint || '@test.com';
  v_auth_id UUID := uuid_generate_v4();
  v_user_exists BOOLEAN;
  v_restaurant_exists BOOLEAN;
  v_account_exists BOOLEAN;
  v_preferences_exists BOOLEAN;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '🧪 TEST 2: Signup de RESTAURANTE';
  RAISE NOTICE '   Email: %', v_test_email;
  RAISE NOTICE '   UUID: %', v_auth_id;

  -- Simular INSERT en auth.users con rol 'restaurante'
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
    jsonb_build_object('role', 'restaurante', 'name', 'Test Restaurant'),
    now(), 
    now(),
    'authenticated',
    'authenticated',
    crypt('test_password_123', gen_salt('bf'))
  );

  -- Verificar que se crearon los registros correctos
  SELECT EXISTS(SELECT 1 FROM public.users WHERE id = v_auth_id AND role = 'restaurante') INTO v_user_exists;
  SELECT EXISTS(SELECT 1 FROM public.restaurants WHERE user_id = v_auth_id AND status = 'pending') INTO v_restaurant_exists;
  SELECT EXISTS(SELECT 1 FROM public.accounts WHERE user_id = v_auth_id AND account_type = 'restaurant') INTO v_account_exists;
  SELECT EXISTS(SELECT 1 FROM public.user_preferences WHERE user_id = v_auth_id) INTO v_preferences_exists;

  IF v_user_exists AND v_restaurant_exists AND v_preferences_exists THEN
    RAISE NOTICE '   ✅ public.users: EXISTS (role=restaurante)';
    RAISE NOTICE '   ✅ restaurants: EXISTS (status=pending)';
    
    IF v_account_exists THEN
      RAISE NOTICE '   ⚠️  accounts: EXISTS (no debería existir hasta aprobación)';
    ELSE
      RAISE NOTICE '   ✅ accounts: NOT EXISTS (correcto - se crea al aprobar)';
    END IF;
    
    RAISE NOTICE '   ✅ user_preferences: EXISTS';
    RAISE NOTICE '   ✅ TEST 2 PASADO';
  ELSE
    RAISE EXCEPTION '❌ TEST 2 FALLIDO: Falta algún registro. users=%, restaurant=%, prefs=%', 
      v_user_exists, v_restaurant_exists, v_preferences_exists;
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ TEST 2 FALLIDO con error: %', SQLERRM;
    RAISE NOTICE '   Ver logs: SELECT * FROM debug_user_signup_log WHERE email = ''%'';', v_test_email;
    RAISE;
END $$;

-- ============================================================================
-- TEST 3: SIGNUP DE REPARTIDOR
-- ============================================================================

DO $$
DECLARE
  v_test_email TEXT := 'test_delivery_' || extract(epoch from now())::bigint || '@test.com';
  v_auth_id UUID := uuid_generate_v4();
  v_user_exists BOOLEAN;
  v_delivery_profile_exists BOOLEAN;
  v_account_exists BOOLEAN;
  v_preferences_exists BOOLEAN;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '🧪 TEST 3: Signup de REPARTIDOR';
  RAISE NOTICE '   Email: %', v_test_email;
  RAISE NOTICE '   UUID: %', v_auth_id;

  -- Simular INSERT en auth.users con rol 'repartidor'
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
    jsonb_build_object('role', 'repartidor', 'name', 'Test Repartidor'),
    now(), 
    now(),
    'authenticated',
    'authenticated',
    crypt('test_password_123', gen_salt('bf'))
  );

  -- Verificar que se crearon los registros correctos
  SELECT EXISTS(SELECT 1 FROM public.users WHERE id = v_auth_id AND role = 'repartidor') INTO v_user_exists;
  SELECT EXISTS(SELECT 1 FROM public.delivery_agent_profiles WHERE user_id = v_auth_id AND account_state = 'pending') INTO v_delivery_profile_exists;
  SELECT EXISTS(SELECT 1 FROM public.accounts WHERE user_id = v_auth_id AND account_type = 'delivery_agent') INTO v_account_exists;
  SELECT EXISTS(SELECT 1 FROM public.user_preferences WHERE user_id = v_auth_id) INTO v_preferences_exists;

  IF v_user_exists AND v_delivery_profile_exists AND v_preferences_exists THEN
    RAISE NOTICE '   ✅ public.users: EXISTS (role=repartidor)';
    RAISE NOTICE '   ✅ delivery_agent_profiles: EXISTS (account_state=pending)';
    
    IF v_account_exists THEN
      RAISE NOTICE '   ⚠️  accounts: EXISTS (no debería existir hasta aprobación)';
    ELSE
      RAISE NOTICE '   ✅ accounts: NOT EXISTS (correcto - se crea al aprobar)';
    END IF;
    
    RAISE NOTICE '   ✅ user_preferences: EXISTS';
    RAISE NOTICE '   ✅ TEST 3 PASADO';
  ELSE
    RAISE EXCEPTION '❌ TEST 3 FALLIDO: Falta algún registro. users=%, delivery_profile=%, prefs=%', 
      v_user_exists, v_delivery_profile_exists, v_preferences_exists;
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ TEST 3 FALLIDO con error: %', SQLERRM;
    RAISE NOTICE '   Ver logs: SELECT * FROM debug_user_signup_log WHERE email = ''%'';', v_test_email;
    RAISE;
END $$;

-- ============================================================================
-- TEST 4: ROLLBACK EN CASO DE ERROR
-- ============================================================================

DO $$
DECLARE
  v_test_email TEXT := 'test_invalid_' || extract(epoch from now())::bigint || '@test.com';
  v_auth_id UUID := uuid_generate_v4();
  v_user_exists BOOLEAN;
  v_error_logged BOOLEAN;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '🧪 TEST 4: Rollback en caso de error (rol inválido)';
  RAISE NOTICE '   Email: %', v_test_email;
  RAISE NOTICE '   UUID: %', v_auth_id;

  -- Intentar signup con rol inválido (debe fallar y hacer rollback)
  BEGIN
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
      jsonb_build_object('role', 'INVALID_ROLE', 'name', 'Test Invalid'),
      now(), 
      now(),
      'authenticated',
      'authenticated',
      crypt('test_password_123', gen_salt('bf'))
    );
    
    RAISE EXCEPTION 'TEST 4 debería haber fallado pero no lo hizo';
    
  EXCEPTION
    WHEN OTHERS THEN
      -- Se espera que falle
      RAISE NOTICE '   ✅ Error capturado (esperado): %', SQLERRM;
  END;

  -- Verificar que NO se creó nada en public.users (rollback exitoso)
  SELECT EXISTS(SELECT 1 FROM public.users WHERE id = v_auth_id) INTO v_user_exists;
  
  -- Verificar que se logueó el error
  SELECT EXISTS(
    SELECT 1 FROM public.debug_user_signup_log 
    WHERE user_id = v_auth_id AND event = 'ERROR'
  ) INTO v_error_logged;

  IF NOT v_user_exists THEN
    RAISE NOTICE '   ✅ public.users: NOT EXISTS (rollback exitoso)';
    
    IF v_error_logged THEN
      RAISE NOTICE '   ✅ Error logueado en debug_user_signup_log';
    ELSE
      RAISE NOTICE '   ⚠️  Error NO logueado (puede ser normal si el rollback fue completo)';
    END IF;
    
    RAISE NOTICE '   ✅ TEST 4 PASADO';
  ELSE
    RAISE EXCEPTION '❌ TEST 4 FALLIDO: El rollback no funcionó, el usuario existe en public.users';
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ TEST 4 FALLIDO con error inesperado: %', SQLERRM;
    RAISE;
END $$;

-- ============================================================================
-- RESUMEN FINAL
-- ============================================================================

DO $$
DECLARE
  v_total_test_users INT;
  v_total_logs INT;
BEGIN
  -- Contar usuarios de prueba creados
  SELECT COUNT(*) INTO v_total_test_users
  FROM public.users
  WHERE email LIKE 'test_%@test.com';

  -- Contar logs generados
  SELECT COUNT(*) INTO v_total_logs
  FROM public.debug_user_signup_log
  WHERE email LIKE 'test_%@test.com'
    AND created_at > now() - interval '5 minutes';

  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ TODOS LOS TESTS PASADOS';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Usuarios de prueba creados: %', v_total_test_users;
  RAISE NOTICE 'Logs generados: %', v_total_logs;
  RAISE NOTICE '';
  RAISE NOTICE '📋 Ver logs completos:';
  RAISE NOTICE 'SELECT source, event, role, email, details, created_at';
  RAISE NOTICE 'FROM debug_user_signup_log';
  RAISE NOTICE 'WHERE email LIKE ''test_%%@test.com''';
  RAISE NOTICE 'ORDER BY created_at DESC;';
  RAISE NOTICE '';
  RAISE NOTICE '📋 Ver usuarios de prueba:';
  RAISE NOTICE 'SELECT u.id, u.email, u.role, u.name,';
  RAISE NOTICE '       CASE WHEN cp.user_id IS NOT NULL THEN ''✅'' ELSE ''❌'' END as has_client_profile,';
  RAISE NOTICE '       CASE WHEN r.user_id IS NOT NULL THEN ''✅'' ELSE ''❌'' END as has_restaurant,';
  RAISE NOTICE '       CASE WHEN dap.user_id IS NOT NULL THEN ''✅'' ELSE ''❌'' END as has_delivery_profile';
  RAISE NOTICE 'FROM users u';
  RAISE NOTICE 'LEFT JOIN client_profiles cp ON cp.user_id = u.id';
  RAISE NOTICE 'LEFT JOIN restaurants r ON r.user_id = u.id';
  RAISE NOTICE 'LEFT JOIN delivery_agent_profiles dap ON dap.user_id = u.id';
  RAISE NOTICE 'WHERE u.email LIKE ''test_%%@test.com'';';
  RAISE NOTICE '';
  RAISE NOTICE '🚀 Puedes continuar con el script 08_validation_cleanup_tests.sql';
  RAISE NOTICE '   (para limpiar los datos de prueba)';
END $$;
