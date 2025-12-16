-- ======================================================================
-- SOLUCION DE EMERGENCIA: DESHABILITAR TRIGGERS PROBLEMÁTICOS
-- ======================================================================

-- 1. Deshabilitar temporalmente los triggers que causan el error
DROP TRIGGER IF EXISTS trigger_process_order_financial_transactions ON orders;
DROP TRIGGER IF EXISTS trigger_process_settlement_completion ON settlements;
DROP TRIGGER IF EXISTS trigger_create_account_on_approval ON users;

-- 2. Mantener solo el trigger esencial para pickup_code (que funciona correctamente)
-- Este trigger sí funciona porque es BEFORE UPDATE
DROP TRIGGER IF EXISTS trigger_generate_pickup_code ON orders;
CREATE TRIGGER trigger_generate_pickup_code
  BEFORE UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION generate_pickup_code();

-- 3. Crear función RPC simplificada para crear órdenes SIN triggers complejos
CREATE OR REPLACE FUNCTION create_order_simple(
  p_user_id UUID,
  p_restaurant_id UUID,
  p_delivery_address TEXT,
  p_delivery_phone VARCHAR(20),
  p_order_notes TEXT DEFAULT NULL,
  p_payment_method VARCHAR(20) DEFAULT 'cash',
  p_total_amount DECIMAL(10,2),
  p_delivery_fee DECIMAL(10,2) DEFAULT 35.00,
  p_items JSONB
) RETURNS UUID AS $$
DECLARE
  new_order_id UUID;
  item JSONB;
BEGIN
  -- Create the main order
  INSERT INTO orders (
    user_id,
    restaurant_id,
    delivery_address,
    delivery_phone,
    order_notes,
    payment_method,
    total_amount,
    delivery_fee,
    status,
    created_at
  ) VALUES (
    p_user_id,
    p_restaurant_id,
    p_delivery_address,
    p_delivery_phone,
    p_order_notes,
    p_payment_method,
    p_total_amount,
    p_delivery_fee,
    'pending',
    now()
  ) RETURNING id INTO new_order_id;

  -- Insert order items
  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    INSERT INTO order_items (
      order_id,
      product_id,
      quantity,
      unit_price,
      subtotal
    ) VALUES (
      new_order_id,
      (item->>'product_id')::UUID,
      (item->>'quantity')::INTEGER,
      (item->>'unit_price')::DECIMAL(10,2),
      (item->>'subtotal')::DECIMAL(10,2)
    );
  END LOOP;

  RETURN new_order_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Grant permissions
GRANT EXECUTE ON FUNCTION create_order_simple TO authenticated;

-- 5. Recrear función de pickup code (simple y que funciona)
CREATE OR REPLACE FUNCTION generate_pickup_code()
RETURNS TRIGGER AS $$
BEGIN
  -- Generate 4-digit pickup code when status changes to ready_for_pickup
  IF NEW.status = 'ready_for_pickup' AND (OLD.status IS NULL OR OLD.status != 'ready_for_pickup') THEN
    NEW.pickup_code = LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 6. Verificar que las tablas de balances existan (sin triggers por ahora)
-- Esto es solo para mostrar saldo 0 en interfaces
DO $$
BEGIN
    -- Check if accounts table exists, create if not
    IF NOT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'accounts') THEN
        CREATE TABLE accounts (
            id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
            user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
            account_type VARCHAR(20) NOT NULL CHECK (account_type IN ('restaurant', 'delivery_agent')),
            balance DECIMAL(10,2) DEFAULT 0.00,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
            UNIQUE(user_id, account_type)
        );
    END IF;

    -- Check if account_transactions table exists, create if not
    IF NOT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'account_transactions') THEN
        CREATE TABLE account_transactions (
            id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
            account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            type VARCHAR(30) NOT NULL,
            amount DECIMAL(10,2) NOT NULL,
            order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
            settlement_id UUID,
            description TEXT,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
        );
    END IF;

    -- Check if settlements table exists, create if not
    IF NOT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'settlements') THEN
        CREATE TABLE settlements (
            id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
            payer_account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            receiver_account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
            amount DECIMAL(10,2) NOT NULL,
            status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'rejected')),
            confirmation_code VARCHAR(4),
            created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
        );
    END IF;
END
$$;

-- 7. Mensaje de confirmación
SELECT 'Triggers problemáticos deshabilitados. Creación de órdenes debe funcionar ahora.' as status;