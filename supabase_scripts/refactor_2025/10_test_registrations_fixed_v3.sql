-- =====================================================
-- SCRIPT DE TEST: VALIDAR FUNCIONES DE REGISTRO
-- =====================================================
-- Este script prueba los 3 RPCs de registro con datos de test
-- y muestra los resultados en formato tabla
-- =====================================================
-- IMPORTANTE: Usar emails únicos cada vez que ejecutes este script
-- =====================================================

-- ====================================
-- TEST 1: REGISTRO DE CLIENTE
-- ====================================
-- Firma: register_client(
--   p_email TEXT,
--   p_password TEXT,
--   p_name TEXT,
--   p_phone TEXT DEFAULT NULL,
--   p_address TEXT DEFAULT NULL,
--   p_lat DOUBLE PRECISION DEFAULT NULL,
--   p_lon DOUBLE PRECISION DEFAULT NULL,
--   p_address_structured JSONB DEFAULT NULL
-- )

SELECT 
  'TEST_CLIENT' as test_name,
  result->>'success' as success,
  result->>'user_id' as user_id,
  result->>'email' as email,
  result->>'name' as name,
  result->>'role' as role,
  result->>'message' as message,
  result->>'error' as error
FROM (
  SELECT public.register_client(
    'test_client_' || floor(random() * 1000000)::TEXT || '@example.com', -- Email único
    'password123', -- p_password
    'Cliente Test', -- p_name
    '+52-1234567890', -- p_phone (opcional)
    'Calle Test 123, Col. Centro', -- p_address (opcional)
    19.4326::DOUBLE PRECISION, -- p_lat (opcional)
    -99.1332::DOUBLE PRECISION, -- p_lon (opcional)
    '{"city": "Ciudad de México", "state": "CDMX", "country": "México"}'::JSONB -- p_address_structured (opcional)
  ) as result
) AS client_test;

-- ====================================
-- TEST 2: REGISTRO DE RESTAURANTE
-- ====================================
-- Firma: register_restaurant(
--   p_email TEXT,
--   p_password TEXT,
--   p_owner_name TEXT,
--   p_phone TEXT,
--   p_restaurant_name TEXT,
--   p_restaurant_description TEXT DEFAULT NULL,
--   p_address TEXT DEFAULT NULL,
--   p_lat DOUBLE PRECISION DEFAULT NULL,
--   p_lon DOUBLE PRECISION DEFAULT NULL,
--   p_address_structured JSONB DEFAULT NULL,
--   p_cuisine_type TEXT DEFAULT NULL
-- )

SELECT 
  'TEST_RESTAURANT' as test_name,
  result->>'success' as success,
  result->>'user_id' as user_id,
  result->>'restaurant_id' as restaurant_id,
  result->>'email' as email,
  result->>'name' as owner_name,
  result->>'restaurant_name' as restaurant_name,
  result->>'role' as role,
  result->>'status' as status,
  result->>'message' as message,
  result->>'error' as error
FROM (
  SELECT public.register_restaurant(
    'test_restaurant_' || floor(random() * 1000000)::TEXT || '@example.com', -- Email único
    'password123', -- p_password
    'Juan Pérez', -- p_owner_name
    '+52-9876543210', -- p_phone
    'Restaurante Test ' || floor(random() * 10000)::TEXT, -- p_restaurant_name (único)
    'Restaurante de prueba con comida deliciosa', -- p_restaurant_description (opcional)
    'Av. Reforma 456, Col. Juárez', -- p_address (opcional)
    19.4270::DOUBLE PRECISION, -- p_lat (opcional)
    -99.1677::DOUBLE PRECISION, -- p_lon (opcional)
    '{"city": "Ciudad de México", "state": "CDMX", "country": "México"}'::JSONB, -- p_address_structured (opcional)
    'Mexicana' -- p_cuisine_type (opcional)
  ) as result
) AS restaurant_test;

-- ====================================
-- TEST 3: REGISTRO DE REPARTIDOR
-- ====================================
-- Firma: register_delivery_agent(
--   p_email TEXT,
--   p_password TEXT,
--   p_name TEXT,
--   p_phone TEXT,
--   p_vehicle_type TEXT DEFAULT 'bicicleta',
--   p_emergency_contact_name TEXT DEFAULT NULL,
--   p_emergency_contact_phone TEXT DEFAULT NULL
-- )

SELECT 
  'TEST_DELIVERY_AGENT' as test_name,
  result->>'success' as success,
  result->>'user_id' as user_id,
  result->>'account_id' as account_id,
  result->>'email' as email,
  result->>'name' as name,
  result->>'role' as role,
  result->>'status' as status,
  result->>'account_state' as account_state,
  result->>'vehicle_type' as vehicle_type,
  result->>'message' as message,
  result->>'error' as error
FROM (
  SELECT public.register_delivery_agent(
    'test_delivery_' || floor(random() * 1000000)::TEXT || '@example.com', -- Email único
    'password123', -- p_password
    'Carlos Mendez', -- p_name
    '+52-5551234567', -- p_phone
    'motocicleta', -- p_vehicle_type (opcional, default: 'bicicleta')
    'María Mendez', -- p_emergency_contact_name (opcional)
    '+52-5559876543' -- p_emergency_contact_phone (opcional)
  ) as result
) AS delivery_test;

-- ====================================
-- RESUMEN: Verificar datos creados
-- ====================================

-- Contar registros en cada tabla
SELECT 
  'RESUMEN' as tipo,
  (SELECT COUNT(*) FROM public.users WHERE created_at > NOW() - INTERVAL '5 minutes') as users_nuevos,
  (SELECT COUNT(*) FROM public.client_profiles WHERE created_at > NOW() - INTERVAL '5 minutes') as clientes_nuevos,
  (SELECT COUNT(*) FROM public.restaurants WHERE created_at > NOW() - INTERVAL '5 minutes') as restaurantes_nuevos,
  (SELECT COUNT(*) FROM public.delivery_agent_profiles WHERE created_at > NOW() - INTERVAL '5 minutes') as delivery_nuevos,
  (SELECT COUNT(*) FROM public.accounts WHERE created_at > NOW() - INTERVAL '5 minutes') as accounts_nuevas,
  (SELECT COUNT(*) FROM public.user_preferences WHERE created_at > NOW() - INTERVAL '5 minutes') as preferences_nuevas,
  (SELECT COUNT(*) FROM public.admin_notifications WHERE created_at > NOW() - INTERVAL '5 minutes') as notificaciones_nuevas;

-- Ver logs recientes
SELECT 
  scope,
  message,
  meta->>'user_id' as user_id,
  meta->>'email' as email,
  created_at
FROM public.debug_logs
WHERE created_at > NOW() - INTERVAL '5 minutes'
ORDER BY created_at DESC
LIMIT 10;
