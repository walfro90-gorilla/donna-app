-- Verificar qué funciones de crear órdenes existen actualmente
SELECT 
    routine_name,
    routine_type,
    data_type as return_type,
    routine_definition
FROM information_schema.routines 
WHERE routine_name LIKE '%create_order%' 
AND routine_schema = 'public'
ORDER BY routine_name;