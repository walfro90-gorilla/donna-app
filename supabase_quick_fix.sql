-- ====================================================================
-- SUPABASE QUICK FIX - Sistema básico para evitar errores de triggers
-- ====================================================================

-- Crear tablas básicas para el sistema de balances (versión simplificada)
CREATE TABLE IF NOT EXISTS accounts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  balance DECIMAL(10,2) DEFAULT 0.00,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id)
);

CREATE TABLE IF NOT EXISTS account_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID REFERENCES accounts(id) ON DELETE CASCADE,
  order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
  amount DECIMAL(10,2) NOT NULL,
  transaction_type VARCHAR(50) NOT NULL,
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS settlements (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID REFERENCES accounts(id) ON DELETE CASCADE,
  amount DECIMAL(10,2) NOT NULL,
  confirmation_code VARCHAR(4) NOT NULL,
  status VARCHAR(20) DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  completed_at TIMESTAMP WITH TIME ZONE
);

-- Función básica para procesar transacciones cuando una orden se marca como 'delivered'
CREATE OR REPLACE FUNCTION process_order_financial_transactions()
RETURNS TRIGGER AS $$
DECLARE
  restaurant_account_id UUID;
  delivery_account_id UUID;
  order_total DECIMAL(10,2);
  delivery_fee DECIMAL(10,2) := 35.00;
  restaurant_amount DECIMAL(10,2);
  delivery_amount DECIMAL(10,2);
BEGIN
  -- Solo procesar cuando el status cambia a 'delivered'
  IF OLD.status != 'delivered' AND NEW.status = 'delivered' THEN
    
    order_total := NEW.total_amount;
    restaurant_amount := order_total - delivery_fee;
    delivery_amount := delivery_fee;
    
    -- Buscar o crear cuenta del restaurante
    INSERT INTO accounts (user_id, balance)
    VALUES (NEW.restaurant_id, 0.00)
    ON CONFLICT (user_id) DO NOTHING;
    
    SELECT id INTO restaurant_account_id 
    FROM accounts 
    WHERE user_id = NEW.restaurant_id;
    
    -- Buscar o crear cuenta del repartidor si hay uno asignado
    IF NEW.delivery_agent_id IS NOT NULL THEN
      INSERT INTO accounts (user_id, balance)
      VALUES (NEW.delivery_agent_id, 0.00)
      ON CONFLICT (user_id) DO NOTHING;
      
      SELECT id INTO delivery_account_id 
      FROM accounts 
      WHERE user_id = NEW.delivery_agent_id;
    END IF;
    
    -- Procesar según método de pago
    IF NEW.payment_method = 'PaymentMethod.cash' THEN
      -- Pago en efectivo: restaurante debe el total, repartidor recibe fee
      
      -- Transacción negativa para restaurante (debe pagar)
      INSERT INTO account_transactions (
        account_id, order_id, amount, transaction_type, description
      ) VALUES (
        restaurant_account_id, NEW.id, -order_total, 'cash_collection', 
        'Cobro en efectivo - debe remitir a plataforma'
      );
      
      -- Actualizar balance del restaurante
      UPDATE accounts 
      SET balance = balance - order_total,
          updated_at = NOW()
      WHERE id = restaurant_account_id;
      
      -- Transacción positiva para repartidor (ganancia por delivery)
      IF delivery_account_id IS NOT NULL THEN
        INSERT INTO account_transactions (
          account_id, order_id, amount, transaction_type, description
        ) VALUES (
          delivery_account_id, NEW.id, delivery_amount, 'delivery_fee', 
          'Comisión por entrega'
        );
        
        -- Actualizar balance del repartidor
        UPDATE accounts 
        SET balance = balance + delivery_amount,
            updated_at = NOW()
        WHERE id = delivery_account_id;
      END IF;
      
    ELSE
      -- Pago con tarjeta: restaurante recibe su parte, repartidor recibe fee
      
      -- Transacción positiva para restaurante (ganancia)
      INSERT INTO account_transactions (
        account_id, order_id, amount, transaction_type, description
      ) VALUES (
        restaurant_account_id, NEW.id, restaurant_amount, 'card_payment', 
        'Pago con tarjeta - ganancia neta'
      );
      
      -- Actualizar balance del restaurante
      UPDATE accounts 
      SET balance = balance + restaurant_amount,
          updated_at = NOW()
      WHERE id = restaurant_account_id;
      
      -- Transacción positiva para repartidor (ganancia por delivery)
      IF delivery_account_id IS NOT NULL THEN
        INSERT INTO account_transactions (
          account_id, order_id, amount, transaction_type, description
        ) VALUES (
          delivery_account_id, NEW.id, delivery_amount, 'delivery_fee', 
          'Comisión por entrega'
        );
        
        -- Actualizar balance del repartidor
        UPDATE accounts 
        SET balance = balance + delivery_amount,
            updated_at = NOW()
        WHERE id = delivery_account_id;
      END IF;
    END IF;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear trigger que se ejecuta automáticamente al actualizar órdenes
DROP TRIGGER IF EXISTS orders_financial_trigger ON orders;
CREATE TRIGGER orders_financial_trigger
  AFTER UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION process_order_financial_transactions();

-- Función para generar código de confirmación aleatorio
CREATE OR REPLACE FUNCTION generate_confirmation_code()
RETURNS VARCHAR(4) AS $$
BEGIN
  RETURN LPAD((FLOOR(RANDOM() * 10000))::VARCHAR, 4, '0');
END;
$$ LANGUAGE plpgsql;

-- Función para crear liquidación con código de confirmación
CREATE OR REPLACE FUNCTION create_settlement(
  p_account_id UUID,
  p_amount DECIMAL(10,2)
)
RETURNS TABLE(settlement_id UUID, confirmation_code VARCHAR(4)) AS $$
DECLARE
  new_settlement_id UUID;
  new_confirmation_code VARCHAR(4);
BEGIN
  -- Generar código único
  LOOP
    new_confirmation_code := generate_confirmation_code();
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM settlements 
      WHERE confirmation_code = new_confirmation_code 
      AND status = 'pending'
    );
  END LOOP;
  
  -- Crear liquidación
  INSERT INTO settlements (account_id, amount, confirmation_code)
  VALUES (p_account_id, p_amount, new_confirmation_code)
  RETURNING id INTO new_settlement_id;
  
  RETURN QUERY SELECT new_settlement_id, new_confirmation_code;
END;
$$ LANGUAGE plpgsql;

-- Habilitar Row Level Security
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE settlements ENABLE ROW LEVEL SECURITY;

-- Políticas de seguridad básicas
CREATE POLICY "Users can view their own account" ON accounts
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can view their own transactions" ON account_transactions
  FOR SELECT USING (
    account_id IN (SELECT id FROM accounts WHERE user_id = auth.uid())
  );

CREATE POLICY "Users can view their own settlements" ON settlements
  FOR SELECT USING (
    account_id IN (SELECT id FROM accounts WHERE user_id = auth.uid())
  );

-- Permitir que el sistema pueda insertar y actualizar
CREATE POLICY "System can manage accounts" ON accounts
  FOR ALL USING (true);

CREATE POLICY "System can manage transactions" ON account_transactions
  FOR ALL USING (true);

CREATE POLICY "System can manage settlements" ON settlements
  FOR ALL USING (true);

COMMIT;