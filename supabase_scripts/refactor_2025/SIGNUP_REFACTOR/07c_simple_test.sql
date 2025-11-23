-- ============================================================================
-- TEST SIMPLE - Probar la nueva función handle_new_user_signup_v2()
-- ============================================================================

-- Limpiar datos de prueba anteriores
DELETE FROM auth.users WHERE email LIKE 'test_%@test.com';
DELETE FROM public.users WHERE email LIKE 'test_%@test.com';

-- Test
DO $$
DECLARE
  v_test_email TEXT := 'test_nuclear_' || extract(epoch from now())::bigint || '@test.com';
  v_auth_id UUID := uuid_generate_v4();
  v_user_role TEXT;
  v_profile_exists BOOLEAN;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🧪 TEST NUCLEAR - Nueva función';
  RAISE NOTICE '========================================';
  RAISE NOTICE '📧 Email: %', v_test_email;
  RAISE NOTICE '🆔 UUID: %', v_auth_id;
  RAISE NOTICE '';
  
  -- Simular signup con rol 'cliente' (español)
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
    jsonb_build_object('role', 'cliente', 'name', 'Test Nuclear Cliente'),
    now(), 
    now(),
    'authenticated',
    'authenticated',
    crypt('test_password_123', gen_salt('bf'))
  );
  
  -- Esperar
  PERFORM pg_sleep(0.5);
  
  -- Verificar
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
    RAISE NOTICE '✅✅✅ TEST PASADO ✅✅✅';
    RAISE NOTICE '   La nueva función funciona correctamente';
    RAISE NOTICE '';
    RAISE NOTICE '🚀 Puedes ejecutar el script completo: 07_validation_test_signup.sql';
  ELSE
    RAISE EXCEPTION '❌ TEST FALLIDO: role=%, profile_exists=%', v_user_role, v_profile_exists;
  END IF;
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ ERROR: %', SQLERRM;
    RAISE NOTICE '';
    RAISE NOTICE '📋 Ver logs:';
    RAISE NOTICE 'SELECT * FROM debug_user_signup_log WHERE email = ''%'' ORDER BY created_at DESC;', v_test_email;
    RAISE;
END $$;
