-- =====================================================
-- FASE 7: TESTING DE REGISTROS (VERSIÓN CON TYPE CASTS)
-- =====================================================
-- Tests completos de los 3 procesos de registro
-- Compatible con Supabase SQL Editor
-- Con type casts explícitos para evitar ambigüedad
-- =====================================================

-- ====================================
-- PASO 1: Limpiar datos de test previos
-- ====================================
DELETE FROM auth.users WHERE email IN (
  'test_client_refactor@example.com',
  'test_restaurant_refactor@example.com',
  'test_delivery_refactor@example.com'
);

-- ====================================
-- PASO 2: TEST 1 - Registro de Cliente
-- ====================================
SELECT public.register_client(
  'test_client_refactor@example.com'::TEXT,
  'password123'::TEXT,
  'Cliente Test Refactor'::TEXT,
  '+1234567890'::TEXT,
  'Calle Test 123'::TEXT,
  19.4326::DOUBLE PRECISION,
  -99.1332::DOUBLE PRECISION,
  '{"city": "Ciudad de México"}'::JSONB
) AS test_1_registro_cliente;

-- ====================================
-- PASO 3: TEST 2 - Registro de Restaurante
-- ====================================
SELECT public.register_restaurant(
  'test_restaurant_refactor@example.com'::TEXT,
  'password123'::TEXT,
  'Juan Pérez'::TEXT,
  '+1234567891'::TEXT,
  'Restaurante Test Refactor'::TEXT,
  'Deliciosa comida mexicana'::TEXT,
  'Av. Reforma 456'::TEXT,
  19.4326::DOUBLE PRECISION,
  -99.1332::DOUBLE PRECISION,
  '{"city": "Ciudad de México"}'::JSONB,
  'Mexicana'::TEXT
) AS test_2_registro_restaurante;

-- ====================================
-- PASO 4: TEST 3 - Registro de Repartidor
-- ====================================
SELECT public.register_delivery_agent(
  'test_delivery_refactor@example.com'::TEXT,
  'password123'::TEXT,
  'Carlos Mendez'::TEXT,
  '+1234567892'::TEXT,
  'motocicleta'::TEXT,
  'María Mendez'::TEXT,
  '+0987654321'::TEXT
) AS test_3_registro_delivery;

-- ====================================
-- PASO 5: Verificar integridad de datos
-- ====================================
SELECT 
  'RESUMEN DE REGISTROS EXITOSOS' AS titulo,
  (SELECT COUNT(*) FROM users WHERE email LIKE '%refactor@example.com') AS total_usuarios,
  (SELECT COUNT(*) FROM client_profiles cp JOIN users u ON cp.user_id = u.id WHERE u.email LIKE '%refactor@example.com') AS perfiles_cliente,
  (SELECT COUNT(*) FROM restaurants r JOIN users u ON r.user_id = u.id WHERE u.email LIKE '%refactor@example.com') AS restaurantes,
  (SELECT COUNT(*) FROM delivery_agent_profiles dp JOIN users u ON dp.user_id = u.id WHERE u.email LIKE '%refactor@example.com') AS repartidores,
  (SELECT COUNT(*) FROM accounts a JOIN users u ON a.user_id = u.id WHERE u.email LIKE '%refactor@example.com') AS cuentas,
  (SELECT COUNT(*) FROM user_preferences up JOIN users u ON up.user_id = u.id WHERE u.email LIKE '%refactor@example.com') AS preferencias,
  (SELECT COUNT(*) FROM admin_notifications WHERE metadata->>'owner_email' LIKE '%refactor@example.com' OR metadata->>'email' LIKE '%refactor@example.com') AS notificaciones;

-- ====================================
-- PASO 6: TEST 4 - Validaciones (deben fallar)
-- ====================================

-- Test: Email duplicado (debe retornar success: false)
SELECT public.register_client(
  'test_client_refactor@example.com'::TEXT,
  'password123'::TEXT,
  'Cliente Duplicado'::TEXT,
  '+9999999999'::TEXT
) AS test_4_email_duplicado;

-- Test: Teléfono duplicado (debe retornar success: false)
SELECT public.register_client(
  'otro_email@example.com'::TEXT,
  'password123'::TEXT,
  'Cliente Duplicado'::TEXT,
  '+1234567890'::TEXT
) AS test_5_telefono_duplicado;

-- Test: Password corto (debe retornar success: false)
SELECT public.register_client(
  'test_short_pass@example.com'::TEXT,
  '123'::TEXT,
  'Cliente Test'::TEXT,
  '+5555555555'::TEXT
) AS test_6_password_corto;

-- Test: Email inválido (debe retornar success: false)
SELECT public.register_client(
  'email_invalido'::TEXT,
  'password123'::TEXT,
  'Cliente Test'::TEXT,
  '+6666666666'::TEXT
) AS test_7_email_invalido;

-- ====================================
-- ✅ RESULTADOS ESPERADOS:
-- ====================================
-- test_1_registro_cliente: {"success": true, "user_id": "...", ...}
-- test_2_registro_restaurante: {"success": true, "user_id": "...", "restaurant_id": "...", ...}
-- test_3_registro_delivery: {"success": true, "user_id": "...", ...}
-- 
-- RESUMEN:
-- - total_usuarios: 3
-- - perfiles_cliente: 1
-- - restaurantes: 1
-- - repartidores: 1
-- - cuentas: 2 (restaurante + delivery)
-- - preferencias: 3 (uno por usuario)
-- - notificaciones: 2 (restaurante + delivery)
--
-- test_4_email_duplicado: {"success": false, "error": "El email ya está registrado"}
-- test_5_telefono_duplicado: {"success": false, "error": "El teléfono ya está registrado"}
-- test_6_password_corto: {"success": false, "error": "La contraseña debe tener al menos 6 caracteres"}
-- test_7_email_invalido: {"success": false, "error": "Email inválido: email_invalido"}
-- ====================================
