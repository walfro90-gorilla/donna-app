-- ================================================================
-- 🏦 SISTEMA "BALANCE CERO" - CORRECCIÓN COMPLETA
-- ================================================================
-- Este script implementa el sistema de contabilidad "Balance Cero" siguiendo
-- las especificaciones exactas del usuario.

-- ================================================================
-- 📋 PASO 1: CREAR LAS CUENTAS VIRTUALES DE LA PLATAFORMA
-- ================================================================

-- 1.1 Crear usuarios virtuales de la plataforma
INSERT INTO public.users (
    id, 
    email, 
    name, 
    role, 
    status, 
    email_verified, 
    created_at
) VALUES 
-- Cuenta de Ingresos de la Plataforma
('00000000-0000-0000-0000-000000000001', 'platform+revenue@donna.app', 'Plataforma - Ingresos', 'platform', 'approved', true, NOW()),
-- Cuenta de Pagos/Flotante de la Plataforma  
('00000000-0000-0000-0000-000000000002', 'platform+payables@donna.app', 'Plataforma - Pagos/Flotante', 'platform', 'approved', true, NOW())
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    role = EXCLUDED.role,
    status = EXCLUDED.status;

-- 1.2 Crear cuentas financieras para la plataforma
INSERT INTO public.accounts (
    user_id, 
    account_type, 
    balance, 
    status, 
    created_at
) VALUES 
-- Cuenta de Ingresos
('00000000-0000-0000-0000-000000000001', 'platform_revenue', 0.00, 'active', NOW()),
-- Cuenta Flotante/Pagos
('00000000-0000-0000-0000-000000000002', 'platform_payables', 0.00, 'active', NOW())
ON CONFLICT (user_id) DO UPDATE SET
    account_type = EXCLUDED.account_type,
    status = EXCLUDED.status;

-- ================================================================
-- 📋 PASO 2: ELIMINAR TRIGGER ACTUAL Y RECREAR CON LÓGICA CORRECTA
-- ================================================================

-- 2.1 Eliminar trigger y función existentes
DROP TRIGGER IF EXISTS trigger_process_order_payment ON orders;
DROP FUNCTION IF EXISTS process_order_payment_v2();

-- 2.2 Crear función corregida con sistema "Balance Cero"
CREATE OR REPLACE FUNCTION process_order_payment_v2()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    -- Variables para IDs de cuentas
    restaurant_account_id uuid;
    delivery_agent_account_id uuid;
    platform_revenue_account_id uuid;
    platform_payables_account_id uuid;
    
    -- Variables para cálculos
    subtotal numeric;
    platform_commission numeric;
    delivery_earning numeric;
    platform_delivery_earning numeric;
    
    -- Variables para verificación
    total_balance_check numeric;
BEGIN
    -- Solo procesar si el status cambió a 'delivered' y no se ha procesado antes
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        
        -- ============================================================
        -- 🔍 OBTENER IDs DE LAS CUENTAS
        -- ============================================================
        
        -- Obtener account_id del restaurante
        SELECT a.id INTO restaurant_account_id
        FROM accounts a
        JOIN restaurants r ON r.user_id = a.user_id  
        WHERE r.id = NEW.restaurant_id;
        
        -- Obtener account_id del repartidor
        SELECT a.id INTO delivery_agent_account_id
        FROM accounts a
        WHERE a.user_id = NEW.delivery_agent_id;
        
        -- Obtener account_id de Ingresos de Plataforma
        SELECT a.id INTO platform_revenue_account_id
        FROM accounts a
        WHERE a.user_id = '00000000-0000-0000-0000-000000000001';
        
        -- Obtener account_id de Pagos/Flotante de Plataforma
        SELECT a.id INTO platform_payables_account_id
        FROM accounts a
        WHERE a.user_id = '00000000-0000-0000-0000-000000000002';
        
        -- Verificar que todas las cuentas existen
        IF restaurant_account_id IS NULL OR delivery_agent_account_id IS NULL OR 
           platform_revenue_account_id IS NULL OR platform_payables_account_id IS NULL THEN
            RAISE EXCEPTION 'Error: No se encontraron todas las cuentas necesarias para procesar el pago';
            RETURN NULL;
        END IF;
        
        -- ============================================================
        -- 💰 CALCULAR VARIABLES FINANCIERAS
        -- ============================================================
        
        -- Calcular subtotal (total menos delivery fee)
        subtotal := NEW.total_amount - NEW.delivery_fee;
        
        -- Calcular comisión de plataforma (20% del subtotal)
        platform_commission := subtotal * 0.20;
        
        -- Calcular ganancia del repartidor (85% del delivery fee)
        delivery_earning := NEW.delivery_fee * 0.85;
        
        -- Calcular ganancia de plataforma por delivery (15% del delivery fee)
        platform_delivery_earning := NEW.delivery_fee - delivery_earning;
        
        -- ============================================================
        -- 📝 CREAR TRANSACCIONES SEGÚN MÉTODO DE PAGO
        -- ============================================================
        
        IF NEW.payment_method = 'cash' THEN
            -- CASO 1: PAGO EN EFECTIVO
            -- El repartidor recolecta el efectivo y debe liquidar
            
            -- 1. Restaurante recibe ingresos por sus productos
            INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
            VALUES (restaurant_account_id, 'ORDER_REVENUE', subtotal, 
                   'Ingreso por pedido #' || NEW.id, NEW.id, NOW());
            
            -- 2. Restaurante paga comisión a plataforma  
            INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
            VALUES (restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission, 
                   'Comisión plataforma 20% - Pedido #' || NEW.id, NEW.id, NOW());
            
            -- 3. Repartidor recibe ganancia por delivery
            INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
            VALUES (delivery_agent_account_id, 'DELIVERY_EARNING', delivery_earning, 
                   'Ganancia delivery - Pedido #' || NEW.id, NEW.id, NOW());
            
            -- 4. Repartidor debe liquidar el efectivo total recolectado
            INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
            VALUES (delivery_agent_account_id, 'CASH_COLLECTED', -NEW.total_amount, 
                   'Efectivo recolectado - Pedido #' || NEW.id, NEW.id, NOW());
            
            -- 5. Plataforma recibe comisión
            INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
            VALUES (platform_revenue_account_id, 'PLATFORM_COMMISSION', platform_commission, 
                   'Comisión 20% - Pedido #' || NEW.id, NEW.id, NOW());
            
            -- 6. Plataforma recibe ganancia por delivery
            INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
            VALUES (platform_revenue_account_id, 'DELIVERY_EARNING', platform_delivery_earning, 
                   'Ganancia delivery 15% - Pedido #' || NEW.id, NEW.id, NOW());
                   
        ELSE 
            -- CASO 2: PAGO CON TARJETA
            -- La plataforma recibe el dinero y ahora lo debe a socios
            
            -- 1. Restaurante recibe ingresos por sus productos
            INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
            VALUES (restaurant_account_id, 'ORDER_REVENUE', subtotal, 
                   'Ingreso por pedido #' || NEW.id, NEW.id, NOW());
            
            -- 2. Restaurante paga comisión a plataforma
            INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
            VALUES (restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission, 
                   'Comisión plataforma 20% - Pedido #' || NEW.id, NEW.id, NOW());
            
            -- 3. Repartidor recibe ganancia por delivery  
            INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
            VALUES (delivery_agent_account_id, 'DELIVERY_EARNING', delivery_earning, 
                   'Ganancia delivery - Pedido #' || NEW.id, NEW.id, NOW());
            
            -- 4. Plataforma recibe comisión
            INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
            VALUES (platform_revenue_account_id, 'PLATFORM_COMMISSION', platform_commission, 
                   'Comisión 20% - Pedido #' || NEW.id, NEW.id, NOW());
            
            -- 5. Plataforma recibe ganancia por delivery
            INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
            VALUES (platform_revenue_account_id, 'DELIVERY_EARNING', platform_delivery_earning, 
                   'Ganancia delivery 15% - Pedido #' || NEW.id, NEW.id, NOW());
            
            -- 6. Plataforma debe el total (cuenta flotante negativa)
            INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
            VALUES (platform_payables_account_id, 'CASH_COLLECTED', -NEW.total_amount, 
                   'Dinero recibido por tarjeta - Pedido #' || NEW.id, NEW.id, NOW());
        END IF;
        
        -- ============================================================
        -- 🔄 ACTUALIZAR BALANCES EN ACCOUNTS
        -- ============================================================
        
        -- Actualizar balance del restaurante
        UPDATE accounts SET balance = (
            SELECT COALESCE(SUM(amount), 0) 
            FROM account_transactions 
            WHERE account_id = restaurant_account_id
        ) WHERE id = restaurant_account_id;
        
        -- Actualizar balance del repartidor
        UPDATE accounts SET balance = (
            SELECT COALESCE(SUM(amount), 0) 
            FROM account_transactions 
            WHERE account_id = delivery_agent_account_id
        ) WHERE id = delivery_agent_account_id;
        
        -- Actualizar balance de Ingresos Plataforma
        UPDATE accounts SET balance = (
            SELECT COALESCE(SUM(amount), 0) 
            FROM account_transactions 
            WHERE account_id = platform_revenue_account_id
        ) WHERE id = platform_revenue_account_id;
        
        -- Actualizar balance de Pagos/Flotante Plataforma
        UPDATE accounts SET balance = (
            SELECT COALESCE(SUM(amount), 0) 
            FROM account_transactions 
            WHERE account_id = platform_payables_account_id
        ) WHERE id = platform_payables_account_id;
        
    END IF;
    
    RETURN NEW;
END;
$$;

-- 2.3 Crear el trigger
CREATE TRIGGER trigger_process_order_payment
    AFTER UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION process_order_payment_v2();

-- ================================================================
-- 📋 PASO 3: FUNCIÓN PARA SETTLEMENTS (LIQUIDACIONES)
-- ================================================================

-- 3.1 Eliminar función existente si existe
DROP TRIGGER IF EXISTS trigger_process_settlement ON settlements;
DROP FUNCTION IF EXISTS process_settlement_completion();

-- 3.2 Crear función para procesar settlements
CREATE OR REPLACE FUNCTION process_settlement_completion()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- Solo procesar si el status cambió a 'completed' y no se ha procesado antes
    IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        
        -- Crear transacción de pago para el pagador (quien paga)
        INSERT INTO account_transactions (account_id, type, amount, description, created_at)
        VALUES (NEW.payer_account_id, 'SETTLEMENT_PAYMENT', NEW.amount, 
               'Pago de liquidación #' || NEW.id, NOW());
        
        -- Crear transacción de recepción para el receptor (quien recibe)
        INSERT INTO account_transactions (account_id, type, amount, description, created_at)
        VALUES (NEW.receiver_account_id, 'SETTLEMENT_RECEPTION', -NEW.amount, 
               'Recepción de liquidación #' || NEW.id, NOW());
        
        -- Actualizar balance del pagador
        UPDATE accounts SET balance = (
            SELECT COALESCE(SUM(amount), 0) 
            FROM account_transactions 
            WHERE account_id = NEW.payer_account_id
        ) WHERE id = NEW.payer_account_id;
        
        -- Actualizar balance del receptor  
        UPDATE accounts SET balance = (
            SELECT COALESCE(SUM(amount), 0) 
            FROM account_transactions 
            WHERE account_id = NEW.receiver_account_id
        ) WHERE id = NEW.receiver_account_id;
        
    END IF;
    
    RETURN NEW;
END;
$$;

-- 3.3 Crear trigger para settlements
CREATE TRIGGER trigger_process_settlement
    AFTER UPDATE ON settlements
    FOR EACH ROW
    EXECUTE FUNCTION process_settlement_completion();

-- ================================================================
-- 📋 PASO 4: VERIFICACIÓN DEL SISTEMA "BALANCE CERO"
-- ================================================================

-- Consulta para verificar que el balance total sea cero
DO $$
DECLARE
    total_balance numeric;
BEGIN
    SELECT COALESCE(SUM(balance), 0) INTO total_balance FROM accounts;
    
    RAISE NOTICE '==============================================';
    RAISE NOTICE '🏦 VERIFICACIÓN DEL SISTEMA BALANCE CERO';
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Total de todos los balances: $%.2f', total_balance;
    
    IF total_balance = 0 THEN
        RAISE NOTICE '✅ SISTEMA BALANCEADO CORRECTAMENTE';
    ELSE
        RAISE NOTICE '❌ ADVERTENCIA: Sistema no balanceado (debe ser $0.00)';
    END IF;
    RAISE NOTICE '==============================================';
END;
$$;

-- ================================================================
-- 📋 PASO 5: CONSULTAS DE VERIFICACIÓN
-- ================================================================

-- Mostrar todas las cuentas y sus balances
SELECT 
    u.email,
    u.name,
    a.account_type,
    a.balance,
    a.status
FROM accounts a
JOIN users u ON u.id = a.user_id
ORDER BY a.account_type, u.name;

-- Mostrar resumen de transacciones por orden
SELECT 
    o.id as order_id,
    o.total_amount,
    o.delivery_fee,
    o.payment_method,
    o.status,
    COUNT(at.id) as num_transactions,
    SUM(at.amount) as total_transactions_sum
FROM orders o
LEFT JOIN account_transactions at ON at.order_id = o.id
WHERE o.status = 'delivered'
GROUP BY o.id, o.total_amount, o.delivery_fee, o.payment_method, o.status
ORDER BY o.created_at DESC;