-- Verificar si la función generate_random_code existe
SELECT 
    routine_name,
    routine_definition
FROM information_schema.routines 
WHERE routine_name = 'generate_random_code'
AND routine_schema = 'public';

-- Ver las órdenes más recientes para verificar códigos
SELECT 
    id,
    confirm_code,
    pickup_code,
    created_at,
    status
FROM orders 
ORDER BY created_at DESC 
LIMIT 5;