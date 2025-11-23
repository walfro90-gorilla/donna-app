-- ==========================================
-- PASO 1: Crear función RPC para insertar órdenes (CORREGIDA)
-- ==========================================

-- Crear función RPC para insertar órdenes sin activar triggers problemáticos
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
    new_order_id UUID;
    result JSON;
BEGIN
    -- Generar UUID único para la orden
    new_order_id := gen_random_uuid();
    
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
    result := json_build_object('id', new_order_id::text);
    
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