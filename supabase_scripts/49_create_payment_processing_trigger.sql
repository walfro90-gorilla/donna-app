-- ================================================================
-- 🏦 TRIGGER AUTOMÁTICO PARA PROCESAR PAGOS CUANDO ORDEN SE ENTREGA
-- ================================================================

-- 📋 FUNCIÓN: Procesar pagos automáticamente cuando orden cambia a 'delivered'
-- Esta función:
-- 1. ✅ Calcula comisiones y pagos
-- 2. ✅ Crea transacciones en account_transactions  
-- 3. ✅ Actualiza balances en accounts
-- 4. ✅ Solo procesa si la orden está realmente entregada
-- ================================================================

CREATE OR REPLACE FUNCTION process_order_payment()
RETURNS TRIGGER AS $$
DECLARE
    v_order_record RECORD;
    v_restaurant_account_id UUID;
    v_delivery_account_id UUID;
    v_restaurant_amount DECIMAL(10,2);
    v_delivery_amount DECIMAL(10,2);
    v_platform_commission DECIMAL(10,2);
    v_commission_rate DECIMAL(4,2) := 0.15; -- 15% comisión de plataforma
BEGIN
    -- 🎯 SOLO procesar si el status cambia a 'delivered'
    IF NEW.status != 'delivered' OR OLD.status = 'delivered' THEN
        RETURN NEW;
    END IF;
    
    -- 🎯 SOLO procesar si tiene delivery_agent_id (orden tomada por repartidor)
    IF NEW.delivery_agent_id IS NULL THEN
        RAISE LOG '⚠️ [PAYMENT_TRIGGER] Orden % sin delivery_agent_id, saltando procesamiento', NEW.id;
        RETURN NEW;
    END IF;
    
    RAISE LOG '💰 [PAYMENT_TRIGGER] Procesando pago para orden: %', NEW.id;
    
    -- 📊 OBTENER datos completos de la orden
    SELECT 
        o.id,
        o.restaurant_id,
        o.delivery_agent_id,
        o.total_amount,
        o.delivery_fee,
        o.status
    INTO v_order_record
    FROM orders o
    WHERE o.id = NEW.id;
    
    -- ✅ VALIDAR que la orden existe
    IF NOT FOUND THEN
        RAISE EXCEPTION '❌ [PAYMENT_TRIGGER] Orden no encontrada: %', NEW.id;
    END IF;
    
    -- 🏪 BUSCAR cuenta del restaurante
    SELECT id INTO v_restaurant_account_id
    FROM accounts 
    WHERE user_id = v_order_record.restaurant_id 
      AND account_type = 'restaurant'
      AND status = 'active'
    LIMIT 1;
    
    -- 🚚 BUSCAR cuenta del repartidor
    SELECT id INTO v_delivery_account_id
    FROM accounts 
    WHERE user_id = v_order_record.delivery_agent_id 
      AND account_type = 'delivery_agent'
      AND status = 'active'
    LIMIT 1;
    
    -- ✅ VALIDAR que ambas cuentas existen
    IF v_restaurant_account_id IS NULL THEN
        RAISE EXCEPTION '❌ [PAYMENT_TRIGGER] Cuenta de restaurante no encontrada para user_id: %', v_order_record.restaurant_id;
    END IF;
    
    IF v_delivery_account_id IS NULL THEN
        RAISE EXCEPTION '❌ [PAYMENT_TRIGGER] Cuenta de repartidor no encontrada para user_id: %', v_order_record.delivery_agent_id;
    END IF;
    
    -- 💰 CALCULAR montos
    v_platform_commission := v_order_record.total_amount * v_commission_rate;
    v_restaurant_amount := v_order_record.total_amount - v_platform_commission;
    v_delivery_amount := COALESCE(v_order_record.delivery_fee, 0);
    
    RAISE LOG '💰 [PAYMENT_TRIGGER] Montos calculados - Restaurant: %, Delivery: %, Commission: %', 
        v_restaurant_amount, v_delivery_amount, v_platform_commission;
    
    -- 🎯 TRANSACCIÓN 1: PAGO AL RESTAURANTE (total - comisión)
    INSERT INTO account_transactions (
        account_id,
        type,
        amount,
        description,
        order_id,
        metadata,
        created_at
    ) VALUES (
        v_restaurant_account_id,
        'credit',
        v_restaurant_amount,
        'Pago por orden entregada (menos comisión 15%)',
        v_order_record.id,
        jsonb_build_object(
            'order_total', v_order_record.total_amount,
            'commission_rate', v_commission_rate,
            'commission_amount', v_platform_commission,
            'net_amount', v_restaurant_amount
        ),
        NOW()
    );
    
    -- 🎯 TRANSACCIÓN 2: PAGO AL REPARTIDOR (delivery fee completo)
    IF v_delivery_amount > 0 THEN
        INSERT INTO account_transactions (
            account_id,
            type,
            amount,
            description,
            order_id,
            metadata,
            created_at
        ) VALUES (
            v_delivery_account_id,
            'credit',
            v_delivery_amount,
            'Pago por entrega completada',
            v_order_record.id,
            jsonb_build_object(
                'delivery_fee', v_delivery_amount,
                'order_total', v_order_record.total_amount
            ),
            NOW()
        );
    END IF;
    
    -- 🏦 ACTUALIZAR balances en accounts
    -- Actualizar balance del restaurante
    UPDATE accounts 
    SET 
        balance = balance + v_restaurant_amount,
        updated_at = NOW()
    WHERE id = v_restaurant_account_id;
    
    -- Actualizar balance del repartidor
    IF v_delivery_amount > 0 THEN
        UPDATE accounts 
        SET 
            balance = balance + v_delivery_amount,
            updated_at = NOW()
        WHERE id = v_delivery_account_id;
    END IF;
    
    RAISE LOG '✅ [PAYMENT_TRIGGER] Pagos procesados correctamente para orden: %', NEW.id;
    
    RETURN NEW;
    
EXCEPTION WHEN OTHERS THEN
    RAISE LOG '❌ [PAYMENT_TRIGGER] Error procesando pago para orden %: %', NEW.id, SQLERRM;
    -- NO fallar el trigger, solo registrar el error
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- 🎯 CREAR TRIGGER
-- ================================================================

-- Eliminar trigger existente si existe
DROP TRIGGER IF EXISTS trigger_process_payment_on_delivery ON orders;

-- Crear trigger que se ejecuta DESPUÉS de actualizar una orden
CREATE TRIGGER trigger_process_payment_on_delivery
    AFTER UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION process_order_payment();

-- ================================================================
-- 🧪 TESTING Y VERIFICACIÓN
-- ================================================================

-- Consulta para verificar el trigger
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE trigger_name = 'trigger_process_payment_on_delivery';

-- Consulta para verificar cuentas existentes
SELECT 
    a.id,
    a.user_id,
    u.name,
    a.account_type,
    a.balance,
    a.status
FROM accounts a
JOIN users u ON u.id = a.user_id
ORDER BY a.account_type, u.name;

-- Consulta para verificar órdenes delivered sin transacciones
SELECT 
    o.id,
    o.restaurant_id,
    o.delivery_agent_id,
    o.total_amount,
    o.delivery_fee,
    o.status,
    COUNT(at.id) as transaction_count
FROM orders o
LEFT JOIN account_transactions at ON at.order_id = o.id
WHERE o.status = 'delivered'
GROUP BY o.id, o.restaurant_id, o.delivery_agent_id, o.total_amount, o.delivery_fee, o.status
ORDER BY o.created_at DESC;

RAISE LOG '🎯 [PAYMENT_TRIGGER] Trigger de procesamiento de pagos creado exitosamente';