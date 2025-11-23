-- =====================================================================
-- GUÍA DE EJECUCIÓN DE PRUEBAS - SISTEMA DE TRANSACCIONES
-- Ejecutar en este orden específico
-- =====================================================================

-- ✅ PASO 1: VERIFICAR ESTADO INICIAL
-- =====================================================================
SELECT '🔍 VERIFICANDO CUENTAS DE PLATAFORMA...' as step;
SELECT * FROM get_accounts_summary() WHERE email LIKE 'platform%';

SELECT '📊 ESTADO INICIAL DEL SISTEMA...' as step;
SELECT * FROM get_platform_financial_summary();

-- ✅ PASO 2: CREAR ORDEN DE PRUEBA
-- =====================================================================
SELECT '📦 CREANDO ORDEN DE PRUEBA...' as step;
SELECT create_test_order(25.00, 3.00) as new_order_id;

-- ✅ PASO 3: OBTENER ID DE LA ORDEN CREADA
-- =====================================================================
-- ⚠️ IMPORTANTE: Copia el UUID de la orden del resultado anterior
-- y reemplázalo en las siguientes queries donde veas 'YOUR_ORDER_ID_HERE'

SELECT '🔍 VERIFICANDO ORDEN CREADA...' as step;
SELECT 
    id,
    status,
    total_amount,
    delivery_fee,
    created_at
FROM orders 
WHERE created_at > NOW() - INTERVAL '5 minutes'
ORDER BY created_at DESC 
LIMIT 1;

-- ✅ PASO 4: SIMULAR FLUJO COMPLETO (REEMPLAZA EL UUID)
-- =====================================================================
-- ⚠️ REEMPLAZA 'YOUR_ORDER_ID_HERE' con el UUID real de tu orden
SELECT '🚀 SIMULANDO FLUJO COMPLETO DE ORDEN...' as step;
-- SELECT simulate_order_flow('YOUR_ORDER_ID_HERE');

-- Alternativa manual paso a paso (más educativo):
-- ⚠️ REEMPLAZA 'YOUR_ORDER_ID_HERE' con el UUID real
/*
UPDATE orders SET status = 'confirmed' WHERE id = 'YOUR_ORDER_ID_HERE';
UPDATE orders SET status = 'preparing' WHERE id = 'YOUR_ORDER_ID_HERE';
UPDATE orders SET status = 'ready_for_pickup', pickup_time = NOW() WHERE id = 'YOUR_ORDER_ID_HERE';
UPDATE orders SET status = 'assigned', assigned_at = NOW() WHERE id = 'YOUR_ORDER_ID_HERE';
UPDATE orders SET status = 'picked_up' WHERE id = 'YOUR_ORDER_ID_HERE';
UPDATE orders SET status = 'in_transit' WHERE id = 'YOUR_ORDER_ID_HERE';

-- 💰 MOMENTO CLAVE: Al cambiar a 'delivered', se procesan las transacciones
UPDATE orders SET status = 'delivered', delivery_time = NOW() WHERE id = 'YOUR_ORDER_ID_HERE';
*/

-- ✅ PASO 5: VERIFICAR TRANSACCIONES CREADAS
-- =====================================================================
SELECT '💰 VERIFICANDO TRANSACCIONES CREADAS...' as step;
-- ⚠️ REEMPLAZA 'YOUR_ORDER_ID_HERE' con el UUID real
-- SELECT * FROM get_order_transactions('YOUR_ORDER_ID_HERE');

-- ✅ PASO 6: VERIFICAR BALANCES ACTUALIZADOS
-- =====================================================================
SELECT '💳 VERIFICANDO BALANCES ACTUALIZADOS...' as step;
SELECT * FROM get_accounts_summary();

-- ✅ PASO 7: RESUMEN FINANCIERO FINAL
-- =====================================================================
SELECT '📊 RESUMEN FINANCIERO FINAL...' as step;
SELECT * FROM get_platform_financial_summary();

-- =====================================================================
-- 🧪 CASOS DE PRUEBA ADICIONALES
-- =====================================================================

-- TEST 1: Orden con diferentes montos
SELECT '🧪 TEST 1: Orden con monto diferente...' as step;
SELECT create_test_order(50.00, 5.00) as test_order_2;

-- TEST 2: Orden sin delivery fee
SELECT '🧪 TEST 2: Orden sin delivery fee...' as step;
SELECT create_test_order(30.00, 0.00) as test_order_3;

-- TEST 3: Orden con monto pequeño
SELECT '🧪 TEST 3: Orden con monto pequeño...' as step;
SELECT create_test_order(8.50, 2.50) as test_order_4;

-- =====================================================================
-- 🔄 PRUEBA DE REVERSIÓN (OPCIONAL)
-- =====================================================================
/*
-- Solo para testing - NO usar en producción sin cuidado
SELECT '🔄 PRUEBA DE REVERSIÓN...' as step;
SELECT reverse_order_transactions('YOUR_ORDER_ID_HERE', 'Test reversal');

-- Verificar reversión
SELECT * FROM get_order_transactions('YOUR_ORDER_ID_HERE');
SELECT * FROM get_accounts_summary();
*/

-- =====================================================================
-- 📋 QUERIES DE MONITOREO CONTINUO
-- =====================================================================

-- Órdenes recientes con sus transacciones
SELECT '📋 ÓRDENES RECIENTES...' as step;
SELECT 
    o.id,
    o.status,
    o.total_amount,
    o.delivery_fee,
    o.created_at,
    o.delivery_time,
    COUNT(at.id) as transaction_count
FROM orders o
LEFT JOIN account_transactions at ON o.id = at.order_id
WHERE o.created_at > NOW() - INTERVAL '1 hour'
GROUP BY o.id, o.status, o.total_amount, o.delivery_fee, o.created_at, o.delivery_time
ORDER BY o.created_at DESC;

-- Transacciones por tipo en la última hora
SELECT '💰 TRANSACCIONES POR TIPO...' as step;
SELECT 
    type,
    COUNT(*) as transaction_count,
    SUM(amount) as total_amount
FROM account_transactions
WHERE created_at > NOW() - INTERVAL '1 hour'
GROUP BY type
ORDER BY total_amount DESC;