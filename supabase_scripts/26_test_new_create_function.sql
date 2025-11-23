-- Probar la nueva función create_order_safe
DO $$
DECLARE
    order_response JSON;
    test_user_id UUID := '11111111-1111-1111-1111-111111111111';
    test_restaurant_id UUID := '22222222-2222-2222-2222-222222222222';
BEGIN
    -- Crear orden de prueba
    SELECT create_order_safe(
        test_user_id,
        test_restaurant_id,
        'Dirección de prueba 123',
        19.4326,
        -99.1332,
        150.00,
        25.00,
        'Orden de prueba con códigos'
    ) INTO order_response;
    
    -- Mostrar resultado
    RAISE NOTICE 'Respuesta de create_order_safe: %', order_response;
    
    -- Verificar que se creó con códigos
    IF order_response->>'success' = 'true' THEN
        RAISE NOTICE 'SUCCESS: Orden creada con confirm_code: % y pickup_code: %', 
            order_response->>'confirm_code', 
            order_response->>'pickup_code';
            
        -- Verificar en la base de datos
        DECLARE
            db_confirm_code VARCHAR(3);
            db_pickup_code VARCHAR(4);
        BEGIN
            SELECT confirm_code, pickup_code 
            INTO db_confirm_code, db_pickup_code
            FROM orders 
            WHERE id = (order_response->>'id')::UUID;
            
            RAISE NOTICE 'Verificación DB - confirm_code: %, pickup_code: %', db_confirm_code, db_pickup_code;
        END;
    ELSE
        RAISE NOTICE 'ERROR: %', order_response->>'error';
    END IF;
    
    -- Limpiar orden de prueba
    DELETE FROM orders WHERE id = (order_response->>'id')::UUID;
    RAISE NOTICE 'Orden de prueba eliminada';
END;
$$;