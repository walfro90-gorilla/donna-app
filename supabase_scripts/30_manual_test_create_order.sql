-- Test manual de creación de orden con códigos
DO $$
DECLARE
    test_result JSON;
    test_user_id UUID := '11111111-1111-1111-1111-111111111111';
    test_restaurant_id UUID := '22222222-2222-2222-2222-222222222222';
    test_delivery_address TEXT := 'Test Address 123';
    test_total_amount DECIMAL := 25.50;
    test_items JSON := '[{"product_id": "33333333-3333-3333-3333-333333333333", "quantity": 2, "unit_price": 12.75, "price_at_time_of_order": 12.75}]';
BEGIN
    RAISE NOTICE 'Probando create_order_safe con parámetros de prueba...';
    
    -- Intentar llamar la función
    SELECT create_order_safe(
        test_user_id,
        test_restaurant_id, 
        test_delivery_address,
        test_total_amount,
        test_items
    ) INTO test_result;
    
    RAISE NOTICE 'Resultado: %', test_result;
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error al ejecutar create_order_safe: %', SQLERRM;
END $$;