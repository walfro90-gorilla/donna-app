-- =====================================================================
-- SISTEMA COMPLETO DE TRANSACCIONES - BALANCE CERO
-- Versión: 2.0 - Con todas las reglas de negocio definidas
-- =====================================================================

-- 1️⃣ FUNCIÓN PRINCIPAL: PROCESAR TRANSACCIONES DE ORDEN
-- =====================================================================
CREATE OR REPLACE FUNCTION process_order_financial_completion(order_uuid UUID)
RETURNS JSON AS $$
DECLARE
    v_order RECORD;
    v_restaurant_account_id UUID;
    v_delivery_account_id UUID;
    v_platform_revenue_account_id UUID;
    v_subtotal DECIMAL(10,2);
    v_commission DECIMAL(10,2);
    v_restaurant_earning DECIMAL(10,2);
    v_delivery_earning DECIMAL(10,2);
    v_result JSON;
BEGIN
    -- Obtener datos de la orden
    SELECT o.*, r.name as restaurant_name, u.name as delivery_agent_name
    INTO v_order
    FROM orders o
    LEFT JOIN restaurants r ON o.restaurant_id = r.id
    LEFT JOIN users u ON o.delivery_agent_id = u.id
    WHERE o.id = order_uuid;

    -- Validar que la orden existe y está en estado correcto
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Order not found');
    END IF;

    IF v_order.status != 'delivered' THEN
        RETURN json_build_object('success', false, 'error', 'Order is not delivered yet');
    END IF;

    -- Verificar que no se hayan procesado ya las transacciones
    IF EXISTS (SELECT 1 FROM account_transactions WHERE order_id = order_uuid) THEN
        RETURN json_build_object('success', false, 'error', 'Transactions already processed for this order');
    END IF;

    -- Obtener cuentas necesarias
    SELECT id INTO v_restaurant_account_id
    FROM accounts 
    WHERE user_id = (SELECT user_id FROM restaurants WHERE id = v_order.restaurant_id)
    AND account_type = 'restaurant';

    SELECT id INTO v_delivery_account_id
    FROM accounts 
    WHERE user_id = v_order.delivery_agent_id
    AND account_type = 'delivery_agent';

    SELECT id INTO v_platform_revenue_account_id
    FROM accounts 
    WHERE user_id = (SELECT id FROM users WHERE email = 'platform+revenue@doarepartos.com')
    AND account_type = 'restaurant';

    -- Validar que todas las cuentas existen
    IF v_restaurant_account_id IS NULL OR v_delivery_account_id IS NULL OR v_platform_revenue_account_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Required accounts not found');
    END IF;

    -- CÁLCULOS FINANCIEROS
    -- Subtotal = total_amount - delivery_fee (comisión solo sobre comida)
    v_subtotal := v_order.total_amount - COALESCE(v_order.delivery_fee, 0);
    
    -- Comisión del 20% sobre subtotal de comida
    v_commission := ROUND(v_subtotal * 0.20, 2);
    
    -- Restaurante recibe 80% del subtotal
    v_restaurant_earning := v_subtotal - v_commission;
    
    -- Delivery agent recibe el delivery fee íntegro
    v_delivery_earning := COALESCE(v_order.delivery_fee, 0);

    -- =====================================================================
    -- CREAR TRANSACCIONES
    -- =====================================================================

    -- 1️⃣ RESTAURANTE RECIBE SU PARTE (80% del subtotal)
    INSERT INTO account_transactions (
        account_id, type, amount, order_id, description, metadata
    ) VALUES (
        v_restaurant_account_id,
        'ORDER_REVENUE',
        v_restaurant_earning,
        order_uuid,
        format('Ingreso por orden #%s - %s', 
               LEFT(order_uuid::text, 8), 
               v_order.restaurant_name),
        json_build_object(
            'order_id', order_uuid,
            'subtotal', v_subtotal,
            'commission_rate', 0.20,
            'commission_amount', v_commission,
            'restaurant_percentage', 0.80
        )
    );

    -- 2️⃣ DELIVERY AGENT RECIBE DELIVERY FEE
    IF v_delivery_earning > 0 THEN
        INSERT INTO account_transactions (
            account_id, type, amount, order_id, description, metadata
        ) VALUES (
            v_delivery_account_id,
            'DELIVERY_EARNING',
            v_delivery_earning,
            order_uuid,
            format('Delivery fee - Orden #%s', LEFT(order_uuid::text, 8)),
            json_build_object(
                'order_id', order_uuid,
                'delivery_fee', v_delivery_earning,
                'delivery_agent', v_order.delivery_agent_name
            )
        );
    END IF;

    -- 3️⃣ PLATAFORMA RECIBE COMISIÓN (20% del subtotal)
    INSERT INTO account_transactions (
        account_id, type, amount, order_id, description, metadata
    ) VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_COMMISSION',
        v_commission,
        order_uuid,
        format('Comisión 20%% - Orden #%s', LEFT(order_uuid::text, 8)),
        json_build_object(
            'order_id', order_uuid,
            'subtotal', v_subtotal,
            'commission_rate', 0.20,
            'restaurant_name', v_order.restaurant_name
        )
    );

    -- =====================================================================
    -- ACTUALIZAR BALANCES
    -- =====================================================================
    
    -- Actualizar balance restaurante
    UPDATE accounts 
    SET balance = balance + v_restaurant_earning,
        updated_at = NOW()
    WHERE id = v_restaurant_account_id;

    -- Actualizar balance delivery agent
    IF v_delivery_earning > 0 THEN
        UPDATE accounts 
        SET balance = balance + v_delivery_earning,
            updated_at = NOW()
        WHERE id = v_delivery_account_id;
    END IF;

    -- Actualizar balance plataforma
    UPDATE accounts 
    SET balance = balance + v_commission,
        updated_at = NOW()
    WHERE id = v_platform_revenue_account_id;

    -- Resultado exitoso
    v_result := json_build_object(
        'success', true,
        'order_id', order_uuid,
        'calculations', json_build_object(
            'total_amount', v_order.total_amount,
            'subtotal', v_subtotal,
            'delivery_fee', v_delivery_earning,
            'commission', v_commission,
            'restaurant_earning', v_restaurant_earning,
            'delivery_earning', v_delivery_earning
        ),
        'transactions_created', 3
    );

    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false, 
            'error', SQLERRM,
            'error_code', SQLSTATE
        );
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- 2️⃣ FUNCIÓN TRIGGER: SE EJECUTA AUTOMÁTICAMENTE
-- =====================================================================
CREATE OR REPLACE FUNCTION trigger_process_order_completion()
RETURNS TRIGGER AS $$
BEGIN
    -- Solo procesar cuando cambia a 'delivered'
    IF OLD.status != 'delivered' AND NEW.status = 'delivered' THEN
        
        -- Actualizar delivery_time si no está establecido
        IF NEW.delivery_time IS NULL THEN
            NEW.delivery_time := NOW();
        END IF;
        
        -- Procesar transacciones financieras
        PERFORM process_order_financial_completion(NEW.id);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- 3️⃣ CREAR EL TRIGGER EN LA TABLA ORDERS
-- =====================================================================
DROP TRIGGER IF EXISTS trigger_order_financial_completion ON orders;

CREATE TRIGGER trigger_order_financial_completion
    AFTER UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION trigger_process_order_completion();

-- =====================================================================
-- 4️⃣ FUNCIÓN DE REVERSIÓN (PARA CANCELACIONES)
-- =====================================================================
CREATE OR REPLACE FUNCTION reverse_order_transactions(order_uuid UUID, reason TEXT DEFAULT 'Order cancellation')
RETURNS JSON AS $$
DECLARE
    v_transaction RECORD;
    v_result JSON;
    v_reversed_count INTEGER := 0;
BEGIN
    -- Solo permitir reversión si la orden no ha sido entregada hace más de 24 horas
    IF EXISTS (
        SELECT 1 FROM orders 
        WHERE id = order_uuid 
        AND status = 'delivered' 
        AND delivery_time < NOW() - INTERVAL '24 hours'
    ) THEN
        RETURN json_build_object('success', false, 'error', 'Cannot reverse transactions older than 24 hours');
    END IF;

    -- Crear transacciones inversas
    FOR v_transaction IN 
        SELECT * FROM account_transactions 
        WHERE order_id = order_uuid 
        ORDER BY created_at DESC
    LOOP
        -- Crear transacción inversa
        INSERT INTO account_transactions (
            account_id, type, amount, order_id, description, metadata
        ) VALUES (
            v_transaction.account_id,
            'SETTLEMENT_PAYMENT', -- Tipo genérico para reversiones
            -v_transaction.amount, -- Cantidad negativa
            order_uuid,
            format('REVERSIÓN: %s - %s', v_transaction.description, reason),
            json_build_object(
                'original_transaction_id', v_transaction.id,
                'reversal_reason', reason,
                'original_type', v_transaction.type
            )
        );
        
        -- Actualizar balance
        UPDATE accounts 
        SET balance = balance - v_transaction.amount,
            updated_at = NOW()
        WHERE id = v_transaction.account_id;
        
        v_reversed_count := v_reversed_count + 1;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'reversed_transactions', v_reversed_count,
        'reason', reason
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql;