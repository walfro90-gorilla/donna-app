-- Debug de la función insert_order_items
-- Ver qué está pasando exactamente

-- 1. Ver la función actual
SELECT 
    routine_name as function_name,
    routine_definition as function_code
FROM information_schema.routines 
WHERE routine_name = 'insert_order_items' 
    AND routine_schema = 'public';

-- 2. Probar con datos reales para ver el problema

DO $$
DECLARE 
    test_order_id UUID;
    test_items JSON;
    result_msg TEXT;
BEGIN
    -- Obtener una orden real
    SELECT id INTO test_order_id FROM orders LIMIT 1;
    
    -- Crear test items con todos los campos requeridos
    test_items := '[
        {
            "product_id": "01234567-89ab-cdef-0123-456789abcdef",
            "quantity": 2,
            "price_at_time_of_order": 15.50
        }
    ]'::JSON;
    
    RAISE NOTICE '🔍 Testing with:';
    RAISE NOTICE '   - Order ID: %', test_order_id;
    RAISE NOTICE '   - Items JSON: %', test_items;
    
    -- Ver qué devuelve json_array_elements
    FOR result_msg IN 
        SELECT 'JSON item: ' || item::TEXT
        FROM json_array_elements(test_items) as item
    LOOP
        RAISE NOTICE '%', result_msg;
    END LOOP;
    
    -- Verificar extracción específica de campos
    SELECT 'price_at_time_of_order from JSON: ' || (item->>'price_at_time_of_order')
    INTO result_msg
    FROM json_array_elements(test_items) as item
    LIMIT 1;
    
    RAISE NOTICE '%', result_msg;
    
END $$;