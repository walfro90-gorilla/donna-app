-- Debug: Ver todos los triggers en la tabla orders
SELECT 
    t.trigger_name,
    t.event_manipulation,
    t.action_timing,
    t.action_statement,
    p.prosrc as function_code
FROM information_schema.triggers t
LEFT JOIN pg_proc p ON p.proname = regexp_replace(t.action_statement, '.*EXECUTE FUNCTION ([^(]+).*', '\1')
WHERE t.event_object_table = 'orders';

-- Ver todas las funciones que podrían estar causando problemas
SELECT 
    proname as function_name,
    prosrc as function_code
FROM pg_proc 
WHERE proname LIKE '%order%' OR proname LIKE '%balance%' OR proname LIKE '%financial%';

-- SOLUCIÓN TEMPORAL: Deshabilitar TODOS los triggers en orders
DROP TRIGGER IF EXISTS update_balance_on_order_insert ON orders;
DROP TRIGGER IF EXISTS update_balance_on_order_update ON orders; 
DROP TRIGGER IF EXISTS financial_update_trigger ON orders;
DROP TRIGGER IF EXISTS balance_update_trigger ON orders;
DROP TRIGGER IF EXISTS order_balance_trigger ON orders;

-- Deshabilitar cualquier trigger que contenga 'balance' o 'financial'
DO $$ 
DECLARE 
    r RECORD;
BEGIN
    FOR r IN (SELECT trigger_name FROM information_schema.triggers WHERE event_object_table = 'orders') 
    LOOP
        EXECUTE 'DROP TRIGGER IF EXISTS ' || r.trigger_name || ' ON orders';
    END LOOP;
END $$;

-- Verificar que no queden triggers
SELECT 
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers 
WHERE event_object_table = 'orders';