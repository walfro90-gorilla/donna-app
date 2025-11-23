-- Test crear orden con códigos
DO $$
DECLARE
    order_response JSON;
    new_order_id UUID;
    test_confirm_code TEXT;
    test_pickup_code TEXT;
BEGIN
    -- Crear orden de prueba
    SELECT create_order_safe(
        '11111111-1111-1111-1111-111111111111'::UUID, -- client_id
        '22222222-2222-2222-2222-222222222222'::UUID, -- restaurant_id
        'Dirección de prueba 123',                    -- delivery_address
        'Notas de prueba',                           -- order_notes
        35.0,                                        -- delivery_fee
        15.0,                                        -- service_fee
        150.0                                        -- total_amount
    ) INTO order_response;

    RAISE NOTICE 'Respuesta completa: %', order_response;
    
    -- Extraer datos del response
    new_order_id := (order_response->>'id')::UUID;
    test_confirm_code := order_response->>'confirm_code';
    test_pickup_code := order_response->>'pickup_code';
    
    RAISE NOTICE 'ID de orden: %', new_order_id;
    RAISE NOTICE 'Código de confirmación: %', test_confirm_code;
    RAISE NOTICE 'Código de pickup: %', test_pickup_code;
    
    -- Verificar que se guardaron en la base de datos
    PERFORM * FROM orders 
    WHERE id = new_order_id 
        AND confirm_code = test_confirm_code 
        AND pickup_code = test_pickup_code;
    
    IF FOUND THEN
        RAISE NOTICE '✅ Orden creada correctamente con códigos en BD';
    ELSE
        RAISE NOTICE '❌ Error: Códigos no coinciden con BD';
    END IF;
    
    -- Rollback para no afectar datos reales
    ROLLBACK;
END $$;