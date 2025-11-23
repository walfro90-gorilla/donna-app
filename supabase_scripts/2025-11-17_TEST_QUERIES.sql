-- ============================================================================
-- QUERIES DE PRUEBA - Funciones RPC Optimizadas
-- ============================================================================
-- PROPÓSITO: Queries para probar y validar las funciones RPC después del deployment
-- FECHA: 2025-11-17
-- AUTOR: Hologram
-- ============================================================================

-- ============================================================================
-- PASO 1: Obtener IDs de prueba de tu base de datos
-- ============================================================================

\echo '📋 [TEST] Obteniendo órdenes de prueba...'

-- Obtener órdenes activas con sus datos básicos
SELECT 
  o.id as order_id,
  o.status,
  o.user_id,
  o.restaurant_id,
  o.delivery_agent_id,
  r.name as restaurant_name,
  u.name as client_name,
  du.name as delivery_agent_name
FROM orders o
LEFT JOIN restaurants r ON r.id = o.restaurant_id
LEFT JOIN users u ON u.id = o.user_id
LEFT JOIN users du ON du.id = o.delivery_agent_id
WHERE o.status IN (
  'pending', 'confirmed', 'in_preparation', 'preparing',
  'ready_for_pickup', 'assigned', 'picked_up', 'on_the_way', 'in_transit'
)
ORDER BY o.created_at DESC
LIMIT 10;

-- ============================================================================
-- PASO 2: Probar get_order_full_details con una orden real
-- ============================================================================

\echo '🧪 [TEST] Probando get_order_full_details...'

-- REEMPLAZAR 'ORDER_ID_AQUI' con un order_id real del query anterior
-- Ejemplo: SELECT get_order_full_details('b9e709f0-c4b3-468b-a315-1d0364cb0bec');

-- Descomenta y reemplaza con tu order_id:
-- SELECT get_order_full_details('ORDER_ID_AQUI');

-- Verificar que el resultado incluye:
-- ✅ id, status, total_amount
-- ✅ restaurant { id, name, user { name, phone } }
-- ✅ delivery_agent { id, name, phone } (si existe)
-- ✅ order_items [ { id, quantity, product { name, price } } ]

-- ============================================================================
-- PASO 3: Verificar estructura del JSON devuelto
-- ============================================================================

\echo '🔍 [TEST] Verificando estructura del JSON...'

-- Query para ver la estructura completa de manera legible
-- REEMPLAZAR 'ORDER_ID_AQUI' con un order_id real

-- Descomenta y reemplaza:
-- SELECT jsonb_pretty(get_order_full_details('ORDER_ID_AQUI'));

-- ============================================================================
-- PASO 4: Probar get_client_active_orders con un usuario real
-- ============================================================================

\echo '🧪 [TEST] Probando get_client_active_orders...'

-- Obtener usuarios que tienen órdenes activas
SELECT DISTINCT 
  o.user_id,
  u.email,
  u.name,
  COUNT(o.id) as active_orders_count
FROM orders o
LEFT JOIN users u ON u.id = o.user_id
WHERE o.status IN (
  'pending', 'confirmed', 'in_preparation', 'preparing',
  'ready_for_pickup', 'assigned', 'picked_up', 'on_the_way', 'in_transit'
)
GROUP BY o.user_id, u.email, u.name
ORDER BY active_orders_count DESC
LIMIT 5;

-- REEMPLAZAR 'USER_ID_AQUI' con un user_id del query anterior
-- Ejemplo: SELECT get_client_active_orders('c7c5e7d1-4511-4690-91a9-127831e26f7e');

-- Descomenta y reemplaza con tu user_id:
-- SELECT get_client_active_orders('USER_ID_AQUI');

-- ============================================================================
-- PASO 5: Verificar el array de órdenes devuelto
-- ============================================================================

\echo '🔍 [TEST] Verificando array de órdenes...'

-- Query para ver el array completo de manera legible
-- REEMPLAZAR 'USER_ID_AQUI' con un user_id real

-- Descomenta y reemplaza:
-- SELECT jsonb_pretty(get_client_active_orders('USER_ID_AQUI'));

-- Verificar que devuelve un array [] con objetos completos
-- Cada objeto debe tener la misma estructura que get_order_full_details

-- ============================================================================
-- PASO 6: Contar órdenes devueltas
-- ============================================================================

\echo '📊 [TEST] Contando órdenes activas...'

-- Query para contar cuántas órdenes devuelve la función
-- REEMPLAZAR 'USER_ID_AQUI' con un user_id real

-- Descomenta y reemplaza:
-- SELECT jsonb_array_length(get_client_active_orders('USER_ID_AQUI')) as total_active_orders;

-- ============================================================================
-- PASO 7: Verificar que solo devuelve status activos
-- ============================================================================

\echo '✅ [TEST] Verificando filtro de status activos...'

-- Query para verificar que NO devuelve órdenes delivered o canceled
-- REEMPLAZAR 'USER_ID_AQUI' con un user_id real

-- Descomenta y reemplaza:
-- SELECT 
--   elem->>'id' as order_id,
--   elem->>'status' as status,
--   elem->'restaurant'->>'name' as restaurant_name
-- FROM jsonb_array_elements(
--   get_client_active_orders('USER_ID_AQUI')
-- ) as elem;

-- Verificar que NINGUNA orden tiene status = 'delivered' o 'canceled'

-- ============================================================================
-- PASO 8: Performance Test - Medir tiempo de ejecución
-- ============================================================================

\echo '⚡ [TEST] Midiendo performance...'

-- Medir tiempo de ejecución de get_order_full_details
-- REEMPLAZAR 'ORDER_ID_AQUI' con un order_id real

-- Descomenta y reemplaza:
-- EXPLAIN ANALYZE
-- SELECT get_order_full_details('ORDER_ID_AQUI');

-- Tiempo esperado: < 50ms para órdenes con pocos items
-- Si es > 100ms, revisar índices en la base de datos

-- ============================================================================
-- PASO 9: Verificar permisos de las funciones
-- ============================================================================

\echo '🔐 [TEST] Verificando permisos...'

-- Query para verificar que las funciones tienen los permisos correctos
SELECT 
  p.proname as function_name,
  pg_get_function_arguments(p.oid) as arguments,
  pg_get_function_result(p.oid) as return_type,
  p.prosecdef as is_security_definer,
  array_agg(DISTINCT acl.grantee::regrole::text) as granted_to
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
LEFT JOIN LATERAL unnest(COALESCE(p.proacl, array[]::aclitem[])) AS acl ON true
WHERE n.nspname = 'public'
  AND p.proname IN ('get_order_full_details', 'get_client_active_orders')
GROUP BY p.proname, p.oid, p.prosecdef
ORDER BY p.proname;

-- Verificar que:
-- ✅ is_security_definer = true (para ambas funciones)
-- ✅ granted_to incluye 'authenticated' y 'anon'

-- ============================================================================
-- PASO 10: Test de casos edge
-- ============================================================================

\echo '🧪 [TEST] Probando casos edge...'

-- Caso 1: Orden que NO existe
SELECT get_order_full_details('00000000-0000-0000-0000-000000000000');
-- Resultado esperado: null o {}

-- Caso 2: Usuario sin órdenes activas
SELECT get_client_active_orders('00000000-0000-0000-0000-000000000000');
-- Resultado esperado: [] (array vacío)

-- Caso 3: Orden SIN delivery agent asignado
-- REEMPLAZAR 'ORDER_ID_PENDING' con un order_id que tenga status='pending'
-- SELECT get_order_full_details('ORDER_ID_PENDING');
-- Verificar que delivery_agent = null (no debe causar error)

-- Caso 4: Orden SIN order items (caso raro pero posible)
-- REEMPLAZAR 'ORDER_ID_SIN_ITEMS' con un order_id sin items
-- SELECT get_order_full_details('ORDER_ID_SIN_ITEMS');
-- Verificar que order_items = [] (array vacío)

-- ============================================================================
-- RESUMEN DE TESTS ESPERADOS
-- ============================================================================

\echo '📋 [SUMMARY] Resumen de tests a ejecutar:'
\echo ''
\echo '1. ✅ Obtener IDs de prueba'
\echo '2. ✅ Probar get_order_full_details con orden real'
\echo '3. ✅ Verificar estructura del JSON'
\echo '4. ✅ Probar get_client_active_orders con usuario real'
\echo '5. ✅ Verificar array de órdenes'
\echo '6. ✅ Contar órdenes devueltas'
\echo '7. ✅ Verificar filtro de status activos'
\echo '8. ✅ Medir performance'
\echo '9. ✅ Verificar permisos'
\echo '10. ✅ Test de casos edge'
\echo ''
\echo '🎯 IMPORTANTE: Reemplazar los placeholders (ORDER_ID_AQUI, USER_ID_AQUI) con IDs reales'
\echo '🎯 de tu base de datos antes de ejecutar cada query de prueba.'
\echo ''

-- ============================================================================
-- FIN DE TESTS
-- ============================================================================
