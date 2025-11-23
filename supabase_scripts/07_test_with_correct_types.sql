-- Test con tipos de datos corregidos
-- Paso 1: Verificar tipos exactos de la función
SELECT 
    p.proname as function_name,
    pg_get_function_arguments(p.oid) as arguments
FROM pg_proc p
WHERE p.proname IN ('create_order_safe', 'insert_order_items');

-- Paso 2: Test con conversiones explícitas de tipos
DO $$
DECLARE
    test_order_id UUID;
    test_user_id UUID;
    test_restaurant_id UUID;
BEGIN
    -- Usar IDs reales de tu base de datos
    SELECT id INTO test_user_id FROM auth.users LIMIT 1;
    SELECT id INTO test_restaurant_id FROM restaurants LIMIT 1;
    
    -- Llamar función con tipos explícitos
    SELECT create_order_safe(
        test_user_id,                              -- p_user_id UUID
        test_restaurant_id,                        -- p_restaurant_id UUID  
        CAST(100.50 AS DECIMAL),                   -- p_total_amount DECIMAL
        'Calle Ejemplo 123'::TEXT,                 -- p_delivery_address TEXT
        CAST(35 AS INTEGER),                       -- p_delivery_fee INTEGER (default)
        ''::TEXT,                                  -- p_order_notes TEXT (default)
        'cash'::TEXT                               -- p_payment_method TEXT (default)
    ) INTO test_order_id;
    
    RAISE NOTICE 'Order creada exitosamente con ID: %', test_order_id;
    
    -- Test de insert_order_items
    PERFORM insert_order_items(
        test_order_id,                             -- p_order_id UUID
        '[{"product_id": "' || (SELECT id FROM products LIMIT 1) || '", "quantity": 2, "unit_price": 25.50, "total_price": 51.00}]'::JSONB  -- p_items JSONB
    );
    
    RAISE NOTICE 'Items insertados exitosamente';
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error: %', SQLERRM;
END $$;