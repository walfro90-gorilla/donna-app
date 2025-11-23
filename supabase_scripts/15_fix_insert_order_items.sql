-- Corregir la función insert_order_items para manejar price_at_time_of_order correctamente

CREATE OR REPLACE FUNCTION insert_order_items(
    p_order_id UUID,
    p_items JSON
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    item JSON;
    product_uuid UUID;
    item_quantity INTEGER;
    item_price NUMERIC;
    inserted_count INTEGER := 0;
    result_message TEXT;
BEGIN
    -- Log de inicio
    RAISE NOTICE '🎯 insert_order_items: Starting for order %', p_order_id;
    RAISE NOTICE '🎯 insert_order_items: Items JSON: %', p_items;
    
    -- Verificar que el order_id existe
    IF NOT EXISTS (SELECT 1 FROM orders WHERE id = p_order_id) THEN
        RAISE EXCEPTION 'Order with ID % does not exist', p_order_id;
    END IF;
    
    -- Procesar cada item del JSON array
    FOR item IN SELECT * FROM json_array_elements(p_items)
    LOOP
        -- Extraer valores del JSON
        product_uuid := (item->>'product_id')::UUID;
        item_quantity := (item->>'quantity')::INTEGER;
        item_price := (item->>'price_at_time_of_order')::NUMERIC;
        
        -- Log de debug para cada item
        RAISE NOTICE '🔍 Processing item:';
        RAISE NOTICE '   - product_id: % (type: %)', product_uuid, pg_typeof(product_uuid);
        RAISE NOTICE '   - quantity: % (type: %)', item_quantity, pg_typeof(item_quantity);
        RAISE NOTICE '   - price_at_time_of_order: % (type: %)', item_price, pg_typeof(item_price);
        
        -- Validar que no sean NULL
        IF product_uuid IS NULL THEN
            RAISE EXCEPTION 'product_id cannot be NULL in item: %', item;
        END IF;
        
        IF item_quantity IS NULL THEN
            RAISE EXCEPTION 'quantity cannot be NULL in item: %', item;
        END IF;
        
        IF item_price IS NULL THEN
            RAISE EXCEPTION 'price_at_time_of_order cannot be NULL in item: %', item;
        END IF;
        
        -- Verificar que el producto existe
        IF NOT EXISTS (SELECT 1 FROM products WHERE id = product_uuid) THEN
            RAISE EXCEPTION 'Product with ID % does not exist', product_uuid;
        END IF;
        
        -- Insertar el item
        INSERT INTO order_items (
            id,
            order_id,
            product_id,
            quantity,
            price_at_time_of_order,
            created_at
        ) VALUES (
            gen_random_uuid(),
            p_order_id,
            product_uuid,
            item_quantity,
            item_price,
            NOW()
        );
        
        inserted_count := inserted_count + 1;
        RAISE NOTICE '✅ Item inserted successfully';
    END LOOP;
    
    -- Retornar mensaje de éxito
    result_message := format('Successfully inserted %s items for order %s', inserted_count, p_order_id);
    RAISE NOTICE '🎉 %', result_message;
    
    RETURN result_message;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error in insert_order_items: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
END;
$$;