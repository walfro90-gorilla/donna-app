-- Verificar la función actual create_order_safe
SELECT 
    p.proname as function_name,
    p.prosrc as function_code
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'create_order_safe'
AND n.nspname = 'public';