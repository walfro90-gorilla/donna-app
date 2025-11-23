-- Actualizar función insert_order_items para usar las columnas correctas
DROP FUNCTION IF EXISTS insert_order_items(UUID, JSON);

CREATE OR REPLACE FUNCTION insert_order_items(
    p_order_id UUID,
    p_items JSON
) RETURNS JSON AS $$
DECLARE
    item JSON;
    result JSON;
BEGIN
    -- Iterar sobre cada item en el JSON
    FOR item IN SELECT * FROM json_array_elements(p_items)
    LOOP
        INSERT INTO order_items (
            id,
            order_id,
            product_id,
            quantity,
            unit_price,
            price_at_time_of_order
        ) VALUES (
            gen_random_uuid(),
            p_order_id,
            (item->>'product_id')::UUID,
            (item->>'quantity')::INTEGER,
            (item->>'unit_price')::NUMERIC,
            (item->>'unit_price')::NUMERIC  -- Usar unit_price también para price_at_time_of_order
        );
    END LOOP;
    
    -- Retornar éxito
    result := json_build_object(
        'success', true,
        'message', 'Order items inserted successfully'
    );
    
    RETURN result;
EXCEPTION
    WHEN OTHERS THEN
        -- Retornar error
        result := json_build_object(
            'success', false,
            'error', SQLERRM
        );
        RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Dar permisos
GRANT EXECUTE ON FUNCTION insert_order_items(UUID, JSON) TO anon;
GRANT EXECUTE ON FUNCTION insert_order_items(UUID, JSON) TO authenticated;