-- ==========================================
-- VERIFICACIÓN SIMPLE DE FUNCIONES
-- ==========================================

-- 1. Verificar que las funciones existen
SELECT 'Functions Check:' AS step;
SELECT proname as function_name, pronargs as parameter_count 
FROM pg_proc 
WHERE proname IN ('create_order_safe', 'insert_order_items');

-- 2. Obtener datos para prueba
SELECT '---' AS separator;
SELECT 'Sample Data:' AS step;

-- Usuarios disponibles
SELECT 'USERS:' AS table_name;
SELECT id, name, email FROM users LIMIT 3;

-- Restaurantes disponibles  
SELECT 'RESTAURANTS:' AS table_name;
SELECT id, name FROM restaurants LIMIT 3;

-- Productos disponibles
SELECT 'PRODUCTS:' AS table_name;
SELECT id, name, price FROM products LIMIT 3;

-- 3. Instrucciones finales
SELECT '---' AS separator;
SELECT 'NEXT STEPS:' AS instruction;
SELECT '1. Copy a user_id from above' AS step_1;
SELECT '2. Copy a restaurant_id from above' AS step_2;  
SELECT '3. Copy some product_ids from above' AS step_3;
SELECT '4. Tell the developer these IDs to create test query' AS step_4;