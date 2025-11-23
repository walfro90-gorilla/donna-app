-- =====================================================================
-- SCRIPTS DE TESTING - SISTEMA DE TRANSACCIONES
-- =====================================================================

-- 1️⃣ CREAR USUARIOS DE PRUEBA (SI NO EXISTEN)
-- =====================================================================
DO $$
BEGIN
    -- Usuario cliente de prueba
    IF NOT EXISTS (SELECT 1 FROM users WHERE email = 'cliente.test@doarepartos.com') THEN
        INSERT INTO users (email, name, role, phone, address, email_confirm)
        VALUES ('cliente.test@doarepartos.com', 'Cliente Test', 'cliente', '+1234567890', 'Calle Test 123', true);
    END IF;

    -- Usuario restaurante de prueba
    IF NOT EXISTS (SELECT 1 FROM users WHERE email = 'restaurant.test@doarepartos.com') THEN
        INSERT INTO users (email, name, role, phone, address, email_confirm)
        VALUES ('restaurant.test@doarepartos.com', 'Restaurante Test', 'restaurant', '+1234567891', 'Av. Restaurant 456', true);
    END IF;

    -- Usuario delivery de prueba
    IF NOT EXISTS (SELECT 1 FROM users WHERE email = 'delivery.test@doarepartos.com') THEN
        INSERT INTO users (email, name, role, phone, address, email_confirm)
        VALUES ('delivery.test@doarepartos.com', 'Delivery Test', 'delivery_agent', '+1234567892', 'Calle Delivery 789', true);
    END IF;
END $$;

-- 2️⃣ CREAR RESTAURANTE Y CUENTAS DE PRUEBA
-- =====================================================================
DO $$
DECLARE
    v_restaurant_user_id UUID;
    v_delivery_user_id UUID;
    v_restaurant_id UUID;
BEGIN
    -- Obtener IDs de usuarios
    SELECT id INTO v_restaurant_user_id FROM users WHERE email = 'restaurant.test@doarepartos.com';
    SELECT id INTO v_delivery_user_id FROM users WHERE email = 'delivery.test@doarepartos.com';

    -- Crear restaurante si no existe
    IF NOT EXISTS (SELECT 1 FROM restaurants WHERE user_id = v_restaurant_user_id) THEN
        INSERT INTO restaurants (user_id, name, address, phone, category, delivery_time, rating)
        VALUES (
            v_restaurant_user_id,
            'Restaurante Test',
            'Av. Restaurant 456',
            '+1234567891',
            'comida_rapida',
            30,
            4.5
        ) RETURNING id INTO v_restaurant_id;
    ELSE
        SELECT id INTO v_restaurant_id FROM restaurants WHERE user_id = v_restaurant_user_id;
    END IF;

    -- Crear cuentas si no existen
    INSERT INTO accounts (user_id, account_type, balance)
    VALUES 
        (v_restaurant_user_id, 'restaurant', 0.00),
        (v_delivery_user_id, 'delivery_agent', 0.00)
    ON CONFLICT (user_id) DO NOTHING;
    
END $$;

-- 3️⃣ FUNCIÓN PARA CREAR ORDEN DE PRUEBA
-- =====================================================================
CREATE OR REPLACE FUNCTION create_test_order(
    p_total_amount DECIMAL(10,2) DEFAULT 25.00,
    p_delivery_fee DECIMAL(10,2) DEFAULT 3.00
)
RETURNS UUID AS $$
DECLARE
    v_customer_id UUID;
    v_restaurant_id UUID;
    v_delivery_agent_id UUID;
    v_order_id UUID;
BEGIN
    -- Obtener IDs necesarios
    SELECT id INTO v_customer_id FROM users WHERE email = 'cliente.test@doarepartos.com';
    SELECT r.id INTO v_restaurant_id 
    FROM restaurants r 
    JOIN users u ON r.user_id = u.id 
    WHERE u.email = 'restaurant.test@doarepartos.com';
    SELECT id INTO v_delivery_agent_id FROM users WHERE email = 'delivery.test@doarepartos.com';

    -- Crear orden
    INSERT INTO orders (
        user_id,
        restaurant_id,
        delivery_agent_id,
        status,
        total_amount,
        delivery_fee,
        payment_method,
        delivery_address
    ) VALUES (
        v_customer_id,
        v_restaurant_id,
        v_delivery_agent_id,
        'pending',
        p_total_amount,
        p_delivery_fee,
        'cash',
        'Dirección de entrega test'
    ) RETURNING id INTO v_order_id;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;

-- 4️⃣ FUNCIÓN PARA SIMULAR FLUJO COMPLETO DE ORDEN
-- =====================================================================
CREATE OR REPLACE FUNCTION simulate_order_flow(p_order_id UUID)
RETURNS JSON AS $$
DECLARE
    v_result JSON;
BEGIN
    -- Paso 1: Confirmar orden
    UPDATE orders SET status = 'confirmed', updated_at = NOW() WHERE id = p_order_id;
    
    -- Paso 2: En preparación
    UPDATE orders SET status = 'preparing', updated_at = NOW() WHERE id = p_order_id;
    
    -- Paso 3: Lista para pickup
    UPDATE orders SET status = 'ready_for_pickup', pickup_time = NOW(), updated_at = NOW() WHERE id = p_order_id;
    
    -- Paso 4: Asignada
    UPDATE orders SET status = 'assigned', assigned_at = NOW(), updated_at = NOW() WHERE id = p_order_id;
    
    -- Paso 5: Recogida
    UPDATE orders SET status = 'picked_up', updated_at = NOW() WHERE id = p_order_id;
    
    -- Paso 6: En camino
    UPDATE orders SET status = 'in_transit', updated_at = NOW() WHERE id = p_order_id;
    
    -- Paso 7: ENTREGADA (Aquí se activan las transacciones)
    UPDATE orders SET status = 'delivered', delivery_time = NOW(), updated_at = NOW() WHERE id = p_order_id;
    
    -- Verificar resultados
    SELECT json_build_object(
        'order_id', p_order_id,
        'status', 'completed',
        'transactions_created', (SELECT COUNT(*) FROM account_transactions WHERE order_id = p_order_id),
        'order_details', (
            SELECT json_build_object(
                'total_amount', total_amount,
                'delivery_fee', delivery_fee,
                'status', status,
                'delivery_time', delivery_time
            )
            FROM orders WHERE id = p_order_id
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- 5️⃣ QUERIES DE VERIFICACIÓN Y MONITOREO
-- =====================================================================

-- Ver estado de todas las cuentas
CREATE OR REPLACE FUNCTION get_accounts_summary()
RETURNS TABLE (
    email TEXT,
    name TEXT,
    role TEXT,
    account_type TEXT,
    balance DECIMAL(10,2),
    transaction_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.email,
        u.name,
        u.role,
        a.account_type,
        a.balance,
        COUNT(at.id) as transaction_count
    FROM users u
    JOIN accounts a ON u.id = a.user_id
    LEFT JOIN account_transactions at ON a.id = at.account_id
    GROUP BY u.email, u.name, u.role, a.account_type, a.balance
    ORDER BY 
        CASE 
            WHEN u.email LIKE 'platform%' THEN 1
            ELSE 2
        END,
        u.email;
END;
$$ LANGUAGE plpgsql;

-- Ver transacciones de una orden específica
CREATE OR REPLACE FUNCTION get_order_transactions(p_order_id UUID)
RETURNS TABLE (
    transaction_id UUID,
    account_owner_email TEXT,
    account_type TEXT,
    transaction_type TEXT,
    amount DECIMAL(10,2),
    description TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        at.id,
        u.email,
        a.account_type,
        at.type,
        at.amount,
        at.description,
        at.created_at
    FROM account_transactions at
    JOIN accounts a ON at.account_id = a.id
    JOIN users u ON a.user_id = u.id
    WHERE at.order_id = p_order_id
    ORDER BY at.created_at;
END;
$$ LANGUAGE plpgsql;

-- Resumen financiero de la plataforma
CREATE OR REPLACE FUNCTION get_platform_financial_summary()
RETURNS JSON AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'total_orders_processed', (
            SELECT COUNT(DISTINCT order_id) 
            FROM account_transactions 
            WHERE order_id IS NOT NULL
        ),
        'total_commission_earned', (
            SELECT COALESCE(SUM(amount), 0) 
            FROM account_transactions 
            WHERE type = 'PLATFORM_COMMISSION'
        ),
        'total_restaurant_earnings', (
            SELECT COALESCE(SUM(amount), 0) 
            FROM account_transactions 
            WHERE type = 'ORDER_REVENUE'
        ),
        'total_delivery_earnings', (
            SELECT COALESCE(SUM(amount), 0) 
            FROM account_transactions 
            WHERE type = 'DELIVERY_EARNING'
        ),
        'platform_balance', (
            SELECT COALESCE(SUM(balance), 0) 
            FROM accounts a
            JOIN users u ON a.user_id = u.id
            WHERE u.email LIKE 'platform%'
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;