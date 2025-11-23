-- Test corregido - extraer UUID del JSON response
DO $$
DECLARE
    test_user_id UUID;
    test_restaurant_id UUID;
    test_product_id UUID;
    order_response JSON;
    new_order_id UUID;
    items_result JSON;
    test_items JSON;
BEGIN
    -- Obtener IDs de prueba
    SELECT id INTO test_user_id FROM users LIMIT 1;
    SELECT id INTO test_restaurant_id FROM restaurants LIMIT 1;
    SELECT id INTO test_product_id FROM products LIMIT 1;
    
    RAISE NOTICE 'Usando User ID: %, Restaurant ID: %, Product ID: %', 
        test_user_id, test_restaurant_id, test_product_id;
    
    -- Crear orden y obtener respuesta JSON
    SELECT create_order_safe(
        test_user_id,
        test_restaurant_id,
        45.50::NUMERIC,
        'Test Address 123',
        35.0::NUMERIC,
        'Test order notes',
        'cash'
    ) INTO order_response;
    
    RAISE NOTICE 'Respuesta de create_order_safe: %', order_response;
    
    -- Extraer el ID de la orden del JSON
    new_order_id := (order_response->>'id')::UUID;
    
    RAISE NOTICE 'ID de orden extraído: %', new_order_id;
    
    -- Verificar que el ID no sea nulo
    IF new_order_id IS NULL THEN
        RAISE EXCEPTION 'No se pudo extraer el ID de la orden del JSON response';
    END IF;
    
    -- Preparar items JSON
    test_items := json_build_array(
        json_build_object(
            'product_id', test_product_id,
            'quantity', 2,
            'unit_price', 22.75
        )
    );
    
    RAISE NOTICE 'Items JSON: %', test_items;
    
    -- Insertar items
    SELECT insert_order_items(new_order_id, test_items) INTO items_result;
    
    RAISE NOTICE 'Resultado insert_order_items: %', items_result;
    
    -- Verificar que los items se insertaron correctamente
    IF (items_result->>'success')::BOOLEAN = true THEN
        RAISE NOTICE '✅ TEST EXITOSO: Orden creada e items insertados correctamente';
    ELSE
        RAISE EXCEPTION '❌ ERROR insertando items: %', items_result->>'error';
    END IF;
    
END $$;