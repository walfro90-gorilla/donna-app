-- =====================================================
-- FASE 7: TESTING DE REGISTROS
-- =====================================================
-- Tests completos de los 3 procesos de registro
-- Tiempo estimado: 15 minutos
-- ⚠️ Ejecutar en ambiente de staging primero
-- =====================================================

-- ====================================
-- PREPARACIÓN: Limpiar datos de test previos
-- ====================================
DO $$
DECLARE
  v_test_emails TEXT[] := ARRAY[
    'test_client_refactor@example.com',
    'test_restaurant_refactor@example.com',
    'test_delivery_refactor@example.com'
  ];
  v_email TEXT;
BEGIN
  FOREACH v_email IN ARRAY v_test_emails LOOP
    -- Eliminar de auth.users (cascadeará a public.users)
    DELETE FROM auth.users WHERE email = v_email;
  END LOOP;
  
  RAISE NOTICE 'Datos de test previos eliminados';
END $$;

-- ====================================
-- TEST 1: Registro de Cliente
-- ====================================
DO $$
DECLARE
  v_result JSONB;
  v_user_id UUID;
  v_profile_exists BOOLEAN;
  v_preferences_exists BOOLEAN;
BEGIN
  RAISE NOTICE '====================================';
  RAISE NOTICE 'TEST 1: REGISTRO DE CLIENTE';
  RAISE NOTICE '====================================';

  -- Ejecutar registro
  v_result := public.register_client(
    'test_client_refactor@example.com',
    'password123',
    'Cliente Test Refactor',
    '+1234567890',
    'Calle Test 123',
    19.4326,
    -99.1332,
    '{"city": "Ciudad de México"}'::jsonb
  );

  -- Verificar resultado
  IF (v_result->>'success')::BOOLEAN = TRUE THEN
    RAISE NOTICE '✅ Cliente registrado exitosamente';
    v_user_id := (v_result->>'user_id')::UUID;
    
    -- Verificar que se creó el perfil
    SELECT EXISTS(SELECT 1 FROM client_profiles WHERE user_id = v_user_id)
    INTO v_profile_exists;
    
    -- Verificar que se crearon las preferencias
    SELECT EXISTS(SELECT 1 FROM user_preferences WHERE user_id = v_user_id)
    INTO v_preferences_exists;
    
    IF v_profile_exists AND v_preferences_exists THEN
      RAISE NOTICE '✅ Perfil y preferencias creados correctamente';
    ELSE
      RAISE WARNING '❌ Faltan datos relacionados';
    END IF;
    
    -- Mostrar datos
    RAISE NOTICE 'User ID: %', v_user_id;
    RAISE NOTICE 'Email: %', v_result->>'email';
    RAISE NOTICE 'Role: %', v_result->>'role';
  ELSE
    RAISE WARNING '❌ Error en registro: %', v_result->>'error';
  END IF;
END $$;

-- ====================================
-- TEST 2: Registro de Restaurante
-- ====================================
DO $$
DECLARE
  v_result JSONB;
  v_user_id UUID;
  v_restaurant_id UUID;
  v_account_exists BOOLEAN;
  v_notification_exists BOOLEAN;
BEGIN
  RAISE NOTICE '====================================';
  RAISE NOTICE 'TEST 2: REGISTRO DE RESTAURANTE';
  RAISE NOTICE '====================================';

  -- Ejecutar registro
  v_result := public.register_restaurant(
    'test_restaurant_refactor@example.com',
    'password123',
    'Juan Pérez',
    '+1234567891',
    'Restaurante Test Refactor',
    'Deliciosa comida mexicana',
    'Av. Reforma 456',
    19.4326,
    -99.1332,
    '{"city": "Ciudad de México"}'::jsonb,
    'Mexicana'
  );

  -- Verificar resultado
  IF (v_result->>'success')::BOOLEAN = TRUE THEN
    RAISE NOTICE '✅ Restaurante registrado exitosamente';
    v_user_id := (v_result->>'user_id')::UUID;
    v_restaurant_id := (v_result->>'restaurant_id')::UUID;
    
    -- Verificar que se creó la cuenta
    SELECT EXISTS(
      SELECT 1 FROM accounts 
      WHERE user_id = v_user_id AND account_type = 'restaurant'
    )
    INTO v_account_exists;
    
    -- Verificar que se creó la notificación
    SELECT EXISTS(
      SELECT 1 FROM admin_notifications 
      WHERE entity_type = 'restaurant' AND entity_id = v_restaurant_id
    )
    INTO v_notification_exists;
    
    IF v_account_exists AND v_notification_exists THEN
      RAISE NOTICE '✅ Cuenta y notificación creadas correctamente';
    ELSE
      RAISE WARNING '❌ Faltan datos relacionados';
    END IF;
    
    -- Mostrar datos
    RAISE NOTICE 'User ID: %', v_user_id;
    RAISE NOTICE 'Restaurant ID: %', v_restaurant_id;
    RAISE NOTICE 'Status: %', v_result->>'status';
  ELSE
    RAISE WARNING '❌ Error en registro: %', v_result->>'error';
  END IF;
END $$;

-- ====================================
-- TEST 3: Registro de Repartidor
-- ====================================
DO $$
DECLARE
  v_result JSONB;
  v_user_id UUID;
  v_profile_exists BOOLEAN;
  v_account_exists BOOLEAN;
  v_notification_exists BOOLEAN;
BEGIN
  RAISE NOTICE '====================================';
  RAISE NOTICE 'TEST 3: REGISTRO DE REPARTIDOR';
  RAISE NOTICE '====================================';

  -- Ejecutar registro
  v_result := public.register_delivery_agent(
    'test_delivery_refactor@example.com',
    'password123',
    'Carlos Mendez',
    '+1234567892',
    'motocicleta',
    'María Mendez',
    '+0987654321'
  );

  -- Verificar resultado
  IF (v_result->>'success')::BOOLEAN = TRUE THEN
    RAISE NOTICE '✅ Repartidor registrado exitosamente';
    v_user_id := (v_result->>'user_id')::UUID;
    
    -- Verificar que se creó el perfil
    SELECT EXISTS(SELECT 1 FROM delivery_agent_profiles WHERE user_id = v_user_id)
    INTO v_profile_exists;
    
    -- Verificar que se creó la cuenta
    SELECT EXISTS(
      SELECT 1 FROM accounts 
      WHERE user_id = v_user_id AND account_type = 'delivery_agent'
    )
    INTO v_account_exists;
    
    -- Verificar que se creó la notificación
    SELECT EXISTS(
      SELECT 1 FROM admin_notifications 
      WHERE entity_type = 'delivery_agent' AND entity_id = v_user_id
    )
    INTO v_notification_exists;
    
    IF v_profile_exists AND v_account_exists AND v_notification_exists THEN
      RAISE NOTICE '✅ Perfil, cuenta y notificación creadas correctamente';
    ELSE
      RAISE WARNING '❌ Faltan datos relacionados';
    END IF;
    
    -- Mostrar datos
    RAISE NOTICE 'User ID: %', v_user_id;
    RAISE NOTICE 'Account State: %', v_result->>'account_state';
    RAISE NOTICE 'Vehicle: %', v_result->>'vehicle_type';
  ELSE
    RAISE WARNING '❌ Error en registro: %', v_result->>'error';
  END IF;
END $$;

-- ====================================
-- TEST 4: Validaciones (deben fallar)
-- ====================================
DO $$
DECLARE
  v_result JSONB;
BEGIN
  RAISE NOTICE '====================================';
  RAISE NOTICE 'TEST 4: VALIDACIONES';
  RAISE NOTICE '====================================';

  -- Test: Email duplicado
  v_result := public.register_client(
    'test_client_refactor@example.com',
    'password123',
    'Cliente Duplicado',
    '+9999999999'
  );
  
  IF (v_result->>'success')::BOOLEAN = FALSE THEN
    RAISE NOTICE '✅ Validación de email duplicado funciona: %', v_result->>'error';
  ELSE
    RAISE WARNING '❌ No detectó email duplicado';
  END IF;

  -- Test: Teléfono duplicado
  v_result := public.register_client(
    'otro_email@example.com',
    'password123',
    'Cliente Duplicado',
    '+1234567890' -- Teléfono ya registrado
  );
  
  IF (v_result->>'success')::BOOLEAN = FALSE THEN
    RAISE NOTICE '✅ Validación de teléfono duplicado funciona: %', v_result->>'error';
  ELSE
    RAISE WARNING '❌ No detectó teléfono duplicado';
  END IF;

  -- Test: Password corto
  v_result := public.register_client(
    'test_short_pass@example.com',
    '123',
    'Cliente Test',
    '+5555555555'
  );
  
  IF (v_result->>'success')::BOOLEAN = FALSE THEN
    RAISE NOTICE '✅ Validación de password corto funciona: %', v_result->>'error';
  ELSE
    RAISE WARNING '❌ No detectó password corto';
  END IF;

  -- Test: Email inválido
  v_result := public.register_client(
    'email_invalido',
    'password123',
    'Cliente Test',
    '+6666666666'
  );
  
  IF (v_result->>'success')::BOOLEAN = FALSE THEN
    RAISE NOTICE '✅ Validación de email inválido funciona: %', v_result->>'error';
  ELSE
    RAISE WARNING '❌ No detectó email inválido';
  END IF;
END $$;

-- ====================================
-- TEST 5: Integridad de datos
-- ====================================
SELECT 
  'RESUMEN DE TESTS' AS titulo,
  (SELECT COUNT(*) FROM users WHERE email LIKE '%refactor@example.com') AS usuarios_creados,
  (SELECT COUNT(*) FROM client_profiles cp JOIN users u ON cp.user_id = u.id WHERE u.email LIKE '%refactor@example.com') AS perfiles_cliente,
  (SELECT COUNT(*) FROM restaurants r JOIN users u ON r.user_id = u.id WHERE u.email LIKE '%refactor@example.com') AS restaurantes,
  (SELECT COUNT(*) FROM delivery_agent_profiles dp JOIN users u ON dp.user_id = u.id WHERE u.email LIKE '%refactor@example.com') AS repartidores,
  (SELECT COUNT(*) FROM accounts a JOIN users u ON a.user_id = u.id WHERE u.email LIKE '%refactor@example.com') AS cuentas,
  (SELECT COUNT(*) FROM user_preferences up JOIN users u ON up.user_id = u.id WHERE u.email LIKE '%refactor@example.com') AS preferencias,
  (SELECT COUNT(*) FROM admin_notifications WHERE metadata->>'owner_email' LIKE '%refactor@example.com' OR metadata->>'email' LIKE '%refactor@example.com') AS notificaciones;

-- ✅ Todos los contadores deben coincidir:
-- - 3 usuarios
-- - 1 perfil cliente
-- - 1 restaurante
-- - 1 repartidor
-- - 2 cuentas (restaurante + delivery)
-- - 3 preferencias
-- - 2 notificaciones (restaurante + delivery)

RAISE NOTICE '====================================';
RAISE NOTICE 'TESTS COMPLETADOS';
RAISE NOTICE '====================================';
