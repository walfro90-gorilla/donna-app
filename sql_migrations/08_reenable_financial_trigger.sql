-- ======================================================================
-- REHABILITAR TRIGGER FINANCIERO PARA account_transactions
-- ======================================================================
-- Este trigger crea las transacciones financieras cuando una orden
-- cambia a status 'delivered', siguiendo el esquema de balance 0.
-- ======================================================================

-- Recrear la función de procesamiento financiero
CREATE OR REPLACE FUNCTION process_order_financial_transactions()
RETURNS TRIGGER AS $$
DECLARE
  restaurant_account_id UUID;
  delivery_account_id UUID;
  product_total DECIMAL(10,2);
  platform_commission DECIMAL(10,2);
  delivery_earning DECIMAL(10,2);
BEGIN
  -- Solo procesar cuando status cambia a 'delivered'
  IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN
    
    -- Obtener cuenta del restaurante
    SELECT a.id INTO restaurant_account_id
    FROM accounts a
    JOIN restaurants r ON r.user_id = a.user_id
    WHERE r.id = NEW.restaurant_id AND a.account_type = 'restaurant';
    
    -- Obtener cuenta del repartidor
    SELECT a.id INTO delivery_account_id
    FROM accounts a
    WHERE a.user_id = NEW.delivery_agent_id AND a.account_type = 'delivery_agent';
    
    -- Calcular montos según schema
    product_total := NEW.total_amount - COALESCE(NEW.delivery_fee, 35.00);
    platform_commission := product_total * 0.20;
    delivery_earning := COALESCE(NEW.delivery_fee, 35.00) * 0.85;
    
    -- Crear transacciones según método de pago
    IF NEW.payment_method = 'cash' THEN
      -- Pago en efectivo: 4 transacciones
      
      -- 1. Restaurant revenue (credit)
      INSERT INTO account_transactions (account_id, type, amount, order_id, description)
      VALUES (restaurant_account_id, 'ORDER_REVENUE', product_total, NEW.id, 
              'Ingreso orden ' || LEFT(NEW.id::TEXT, 8) || '...')
      ON CONFLICT DO NOTHING;
      
      -- 2. Platform commission (debit)
      INSERT INTO account_transactions (account_id, type, amount, order_id, description)
      VALUES (restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission, NEW.id, 
              'Comisión plataforma orden ' || LEFT(NEW.id::TEXT, 8) || '...')
      ON CONFLICT DO NOTHING;
      
      -- 3. Delivery earning (credit)
      INSERT INTO account_transactions (account_id, type, amount, order_id, description)
      VALUES (delivery_account_id, 'DELIVERY_EARNING', delivery_earning, NEW.id, 
              'Ganancia delivery orden ' || LEFT(NEW.id::TEXT, 8) || '...')
      ON CONFLICT DO NOTHING;
      
      -- 4. Cash collected (debit)
      INSERT INTO account_transactions (account_id, type, amount, order_id, description)
      VALUES (delivery_account_id, 'CASH_COLLECTED', -NEW.total_amount, NEW.id, 
              'Efectivo recolectado orden ' || LEFT(NEW.id::TEXT, 8) || '...')
      ON CONFLICT DO NOTHING;
      
    ELSE
      -- Pago con tarjeta: 3 transacciones (sin recolección de efectivo)
      
      -- 1. Restaurant revenue (credit)
      INSERT INTO account_transactions (account_id, type, amount, order_id, description)
      VALUES (restaurant_account_id, 'ORDER_REVENUE', product_total, NEW.id, 
              'Ingreso orden ' || LEFT(NEW.id::TEXT, 8) || '...')
      ON CONFLICT DO NOTHING;
      
      -- 2. Platform commission (debit)
      INSERT INTO account_transactions (account_id, type, amount, order_id, description)
      VALUES (restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission, NEW.id, 
              'Comisión plataforma orden ' || LEFT(NEW.id::TEXT, 8) || '...')
      ON CONFLICT DO NOTHING;
      
      -- 3. Delivery earning (credit)
      INSERT INTO account_transactions (account_id, type, amount, order_id, description)
      VALUES (delivery_account_id, 'DELIVERY_EARNING', delivery_earning, NEW.id, 
              'Ganancia delivery orden ' || LEFT(NEW.id::TEXT, 8) || '...')
      ON CONFLICT DO NOTHING;
    END IF;
    
    -- Actualizar balances de las cuentas
    UPDATE accounts 
    SET balance = (
      SELECT COALESCE(SUM(amount), 0) 
      FROM account_transactions 
      WHERE account_id = accounts.id
    ),
    updated_at = now()
    WHERE id IN (restaurant_account_id, delivery_account_id);
    
    RAISE NOTICE '[FINANCIAL_TRIGGER] Transacciones creadas para orden % (método: %)', NEW.id, NEW.payment_method;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recrear el trigger
DROP TRIGGER IF EXISTS trigger_process_order_financial_transactions ON orders;
CREATE TRIGGER trigger_process_order_financial_transactions
  AFTER UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION process_order_financial_transactions();

-- Mensaje de confirmación
SELECT 'Trigger financiero rehabilitado exitosamente' as status;
