-- Recrear la función create_order_safe con generación de códigos
CREATE OR REPLACE FUNCTION create_order_safe(
    p_user_id UUID,
    p_restaurant_id UUID,
    p_delivery_address TEXT,
    p_delivery_latitude DECIMAL,
    p_delivery_longitude DECIMAL,
    p_total_amount DECIMAL,
    p_delivery_fee DECIMAL DEFAULT 0,
    p_order_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    new_order_id UUID;
    confirm_code_generated VARCHAR(3);
    pickup_code_generated VARCHAR(4);
    result JSON;
BEGIN
    -- Generar códigos aleatorios
    confirm_code_generated := LPAD(FLOOR(RANDOM() * 1000)::INTEGER::TEXT, 3, '0');
    pickup_code_generated := LPAD(FLOOR(RANDOM() * 10000)::INTEGER::TEXT, 4, '0');
    
    -- Log para debugging
    RAISE NOTICE 'Generando códigos - confirm_code: %, pickup_code: %', confirm_code_generated, pickup_code_generated;
    
    -- Insertar la nueva orden con códigos
    INSERT INTO orders (
        user_id,
        restaurant_id,
        delivery_address,
        delivery_latitude,
        delivery_longitude,
        total_amount,
        delivery_fee,
        order_notes,
        status,
        confirm_code,
        pickup_code,
        created_at,
        updated_at
    ) VALUES (
        p_user_id,
        p_restaurant_id,
        p_delivery_address,
        p_delivery_latitude,
        p_delivery_longitude,
        p_total_amount,
        p_delivery_fee,
        p_order_notes,
        'pending',
        confirm_code_generated,
        pickup_code_generated,
        NOW(),
        NOW()
    ) RETURNING id INTO new_order_id;
    
    -- Log para verificar inserción
    RAISE NOTICE 'Orden creada con ID: %, confirm_code: %, pickup_code: %', new_order_id, confirm_code_generated, pickup_code_generated;
    
    -- Devolver resultado con códigos incluidos
    result := json_build_object(
        'success', true,
        'id', new_order_id,
        'confirm_code', confirm_code_generated,
        'pickup_code', pickup_code_generated,
        'status', 'pending',
        'message', 'Orden creada exitosamente'
    );
    
    RETURN result;
    
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error al crear orden: %', SQLERRM;
    RETURN json_build_object(
        'success', false,
        'error', SQLERRM,
        'message', 'Error al crear la orden'
    );
END;
$$;