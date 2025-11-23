-- Función para generar códigos random
CREATE OR REPLACE FUNCTION generate_random_code(length INTEGER)
RETURNS TEXT AS $$
DECLARE
    chars TEXT := '0123456789';
    result TEXT := '';
    i INTEGER;
BEGIN
    FOR i IN 1..length LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::INTEGER, 1);
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Actualizar función create_order_safe para generar códigos
CREATE OR REPLACE FUNCTION create_order_safe(
    p_client_id UUID,
    p_restaurant_id UUID,
    p_delivery_address TEXT,
    p_order_notes TEXT DEFAULT NULL,
    p_delivery_fee NUMERIC DEFAULT 0,
    p_service_fee NUMERIC DEFAULT 0,
    p_total_amount NUMERIC DEFAULT 0
)
RETURNS JSON AS $$
DECLARE
    v_order_id UUID;
    v_confirm_code TEXT;
    v_pickup_code TEXT;
    result JSON;
BEGIN
    -- Generar códigos únicos
    LOOP
        v_confirm_code := generate_random_code(3);
        EXIT WHEN NOT EXISTS (SELECT 1 FROM orders WHERE confirm_code = v_confirm_code);
    END LOOP;
    
    LOOP
        v_pickup_code := generate_random_code(4);
        EXIT WHEN NOT EXISTS (SELECT 1 FROM orders WHERE pickup_code = v_pickup_code);
    END LOOP;

    -- Generar ID único para la orden
    v_order_id := gen_random_uuid();

    -- Insertar la orden con códigos
    INSERT INTO orders (
        id,
        client_id,
        restaurant_id,
        delivery_address,
        order_notes,
        delivery_fee,
        service_fee,
        total_amount,
        status,
        confirm_code,
        pickup_code,
        created_at,
        updated_at
    ) VALUES (
        v_order_id,
        p_client_id,
        p_restaurant_id,
        p_delivery_address,
        p_order_notes,
        p_delivery_fee,
        p_service_fee,
        p_total_amount,
        'pending',
        v_confirm_code,
        v_pickup_code,
        NOW(),
        NOW()
    );

    -- Construir respuesta JSON
    result := json_build_object(
        'success', true,
        'id', v_order_id,
        'confirm_code', v_confirm_code,
        'pickup_code', v_pickup_code,
        'status', 'pending',
        'message', 'Orden creada exitosamente con códigos generados'
    );

    RAISE NOTICE 'Orden creada: ID=%, ConfirmCode=%, PickupCode=%', v_order_id, v_confirm_code, v_pickup_code;

    RETURN result;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error en create_order_safe: %', SQLERRM;
        RETURN json_build_object(
            'success', false,
            'error', SQLERRM,
            'message', 'Error al crear la orden'
        );
END;
$$ LANGUAGE plpgsql;