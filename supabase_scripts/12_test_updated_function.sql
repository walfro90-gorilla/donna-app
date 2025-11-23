-- Test de la función actualizada insert_order_items
SELECT 
    'Probando función actualizada...' as paso;

-- Obtener IDs para el test
WITH test_data AS (
    SELECT 
        (SELECT id FROM users LIMIT 1) as user_id,
        (SELECT id FROM restaurants LIMIT 1) as restaurant_id,
        (SELECT id FROM products LIMIT 1) as product_id
)
SELECT 
    user_id,
    restaurant_id,
    product_id
FROM test_data;

-- Test completo: crear orden y agregar items
DO $$
DECLARE
    test_user_id UUID;
    test_restaurant_id UUID;
    test_product_id UUID;
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
    
    -- Crear orden
    SELECT create_order_safe(
        test_user_id,
        test_restaurant_id,
        45.50::NUMERIC,
        'Test Address 123',
        35.0::NUMERIC,
        'Test order notes',
        'cash'
    ) INTO new_order_id;
    
    RAISE NOTICE 'Nueva orden creada con ID: %', new_order_id;
    
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
    
END $$;