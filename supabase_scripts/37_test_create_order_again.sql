-- 🧪 TEST FINAL: Crear una orden de prueba y verificar códigos
-- Ahora que tenemos la función generate_random_code, probemos create_order_safe

DO $$
DECLARE
    order_response JSON;
    new_order_id UUID;
    test_user_id UUID;
    test_restaurant_id UUID;
BEGIN
    -- Obtener IDs reales de la base de datos
    SELECT id INTO test_user_id FROM users WHERE role = 'cliente' LIMIT 1;
    SELECT id INTO test_restaurant_id FROM restaurants LIMIT 1;
    
    RAISE NOTICE 'Test User ID: %', test_user_id;
    RAISE NOTICE 'Test Restaurant ID: %', test_restaurant_id;
    
    -- Llamar a la función create_order_safe
    SELECT create_order_safe(
        test_user_id,
        test_restaurant_id,
        'Test Address 123',
        100.00,
        35.00,
        'Test order notes',
        'cash'
    ) INTO order_response;
    
    RAISE NOTICE 'Order Response: %', order_response;
    
    -- Extraer el ID de la orden del JSON
    new_order_id := (order_response->>'id')::UUID;
    RAISE NOTICE 'New Order ID: %', new_order_id;
    
    -- Verificar los códigos generados
    SELECT 
        id,
        confirm_code,
        pickup_code,
        total_amount,
        delivery_address
    FROM orders 
    WHERE id = new_order_id;
    
    -- Limpiar datos de prueba
    DELETE FROM orders WHERE id = new_order_id;
    RAISE NOTICE 'Test order cleaned up';
    
END $$;