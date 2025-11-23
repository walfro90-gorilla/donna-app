-- 🔍 DEBUG: ¿Por qué no se generan los códigos?
-- Vamos a hacer un diagnóstico completo de la función create_order_safe

-- 1. Verificar si existe la función generate_random_code
SELECT routine_name, routine_type 
FROM information_schema.routines 
WHERE routine_name = 'generate_random_code'
AND routine_schema = 'public';

-- 2. Verificar si existe la función create_order_safe y su definición
SELECT routine_name, routine_definition
FROM information_schema.routines 
WHERE routine_name = 'create_order_safe'
AND routine_schema = 'public';

-- 3. Verificar permisos en la tabla orders
SELECT * FROM information_schema.table_privileges 
WHERE table_name = 'orders' 
AND privilege_type = 'INSERT';