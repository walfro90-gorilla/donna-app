-- Crear función RPC para insertar órdenes sin activar triggers
CREATE OR REPLACE FUNCTION create_order_safe(
    p_user_id UUID,
    p_restaurant_id UUID,
    p_total_amount DECIMAL,
    p_delivery_address TEXT,
    p_delivery_fee DECIMAL DEFAULT 35,
    p_order_notes TEXT DEFAULT '',
    p_payment_method TEXT DEFAULT 'cash'
)
RETURNS JSON AS $$
DECLARE
    new_order_id BIGINT;
    result JSON;
BEGIN
    -- Generar ID único para la orden
    new_order_id := EXTRACT(EPOCH FROM NOW()) * 1000 + (RANDOM() * 1000)::INTEGER;
    
    -- Insertar orden directamente sin activar triggers
    INSERT INTO orders (
        id,
        user_id,
        restaurant_id,
        status,
        total_amount,
        delivery_fee,
        delivery_address,
        order_notes,
        payment_method,
        created_at
    ) VALUES (
        new_order_id,
        p_user_id,
        p_restaurant_id,
        'pending',
        p_total_amount,
        p_delivery_fee,
        p_delivery_address,
        p_order_notes,
        p_payment_method,
        NOW()
    );
    
    -- Retornar el ID de la orden creada
    result := json_build_object('id', new_order_id);
    
    RETURN result;
EXCEPTION
    WHEN OTHERS THEN
        -- Log del error para debugging
        RAISE NOTICE 'Error in create_order_safe: %', SQLERRM;
        RETURN json_build_object('error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Dar permisos para que cualquier usuario autenticado pueda usar esta función
GRANT EXECUTE ON FUNCTION create_order_safe TO authenticated;

-- Función para insertar items de orden
CREATE OR REPLACE FUNCTION insert_order_items(
    p_order_id BIGINT,
    p_items JSON
)
RETURNS JSON AS $$
DECLARE
    item JSON;
    result JSON;
    items_inserted INTEGER := 0;
BEGIN
    -- Iterar sobre los items y insertarlos
    FOR item IN SELECT * FROM json_array_elements(p_items)
    LOOP
        INSERT INTO order_items (
            order_id,
            product_id,
            quantity,
            unit_price
        ) VALUES (
            p_order_id,
            (item->>'product_id')::UUID,
            (item->>'quantity')::INTEGER,
            (item->>'unit_price')::DECIMAL
        );
        
        items_inserted := items_inserted + 1;
    END LOOP;
    
    result := json_build_object('items_inserted', items_inserted);
    
    RETURN result;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error in insert_order_items: %', SQLERRM;
        RETURN json_build_object('error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Dar permisos
GRANT EXECUTE ON FUNCTION insert_order_items TO authenticated;