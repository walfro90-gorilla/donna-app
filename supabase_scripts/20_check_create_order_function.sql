-- Verificar función create_order_safe actual
SELECT 
    routine_name,
    routine_definition
FROM information_schema.routines 
WHERE routine_name = 'create_order_safe' 
    AND routine_schema = 'public';