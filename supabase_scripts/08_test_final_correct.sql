-- Test final con tipos exactos correctos
DO $$
DECLARE
    test_order_id UUID;
    test_user_id UUID;
    test_restaurant_id UUID;
    test_product_id UUID;
BEGIN
    -- Obtener IDs reales
    SELECT id INTO test_user_id FROM auth.users LIMIT 1;
    SELECT id INTO test_restaurant_id FROM restaurants LIMIT 1;
    SELECT id INTO test_product_id FROM products LIMIT 1;
    
    RAISE NOTICE 'Usando User ID: %', test_user_id;
    RAISE NOTICE 'Usando Restaurant ID: %', test_restaurant_id;
    RAISE NOTICE 'Usando Product ID: %', test_product_id;
    
    -- Crear orden con tipos exactos
    SELECT create_order_safe(
        test_user_id,                              -- p_user_id UUID
        test_restaurant_id,                        -- p_restaurant_id UUID  
        100.50::NUMERIC,                           -- p_total_amount NUMERIC
        'Calle Ejemplo 123',                       -- p_delivery_address TEXT
        35::NUMERIC,                               -- p_delivery_fee NUMERIC (default)
        '',                                        -- p_order_notes TEXT (default)
        'cash'                                     -- p_payment_method TEXT (default)
    ) INTO test_order_id;
    
    RAISE NOTICE 'Order creada exitosamente con ID: %', test_order_id;
    
    -- Insertar items con JSON (no JSONB)
    PERFORM insert_order_items(
        test_order_id,                             -- p_order_id UUID
        ('[{"product_id": "' || test_product_id || '", "quantity": 2, "unit_price": 25.50, "total_price": 51.00}]')::JSON  -- p_items JSON
    );
    
    RAISE NOTICE '✅ Items insertados exitosamente';
    RAISE NOTICE '🎉 TEST COMPLETADO - Las funciones funcionan correctamente';
    
    -- Limpiar datos de prueba
    DELETE FROM order_items WHERE order_id = test_order_id;
    DELETE FROM orders WHERE id = test_order_id;
    RAISE NOTICE '🧹 Datos de prueba eliminados';
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '❌ Error: %', SQLERRM;
END $$;