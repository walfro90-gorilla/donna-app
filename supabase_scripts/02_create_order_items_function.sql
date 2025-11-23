-- ==========================================
-- PASO 2: Crear función RPC para insertar items de orden
-- ==========================================

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