-- Financial System Migration for Doa Repartos
-- Implements accounts, account_transactions, and settlements tables

-- Create accounts table (one per approved restaurant/delivery agent)
CREATE TABLE IF NOT EXISTS accounts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  account_type TEXT CHECK (account_type IN ('restaurant', 'delivery_agent')) NOT NULL,
  balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  
  -- Ensure only one account per user
  UNIQUE(user_id)
);

-- Create account_transactions table (immutable ledger)
CREATE TABLE IF NOT EXISTS account_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID REFERENCES accounts(id) ON DELETE CASCADE,
  type TEXT CHECK (type IN (
    'ORDER_REVENUE',           -- Restaurant earnings from order
    'PLATFORM_COMMISSION',     -- Platform commission deduction
    'DELIVERY_EARNING',        -- Delivery agent earnings
    'CASH_COLLECTED',          -- Cash collected by delivery agent
    'SETTLEMENT_PAYMENT',      -- Settlement payment from delivery agent
    'SETTLEMENT_RECEPTION'     -- Settlement reception by restaurant
  )) NOT NULL,
  amount DECIMAL(10,2) NOT NULL, -- Positive for credits, negative for debits
  order_id UUID REFERENCES orders(id) ON DELETE SET NULL, -- Link to related order
  settlement_id UUID, -- Link to related settlement (will reference settlements table)
  description TEXT,
  metadata JSONB, -- Additional transaction details
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create settlements table (cash settlement process)
CREATE TABLE IF NOT EXISTS settlements (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  payer_account_id UUID REFERENCES accounts(id) ON DELETE CASCADE,
  receiver_account_id UUID REFERENCES accounts(id) ON DELETE CASCADE,
  amount DECIMAL(10,2) NOT NULL CHECK (amount > 0),
  status TEXT CHECK (status IN ('pending', 'completed', 'cancelled')) DEFAULT 'pending',
  confirmation_code TEXT NOT NULL, -- 4-digit code for verification
  initiated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE,
  completed_by UUID REFERENCES users(id), -- Restaurant user who confirmed
  notes TEXT
);

-- Add settlement_id foreign key constraint to account_transactions
-- (after settlements table exists)
ALTER TABLE account_transactions 
ADD CONSTRAINT fk_settlement_id 
FOREIGN KEY (settlement_id) REFERENCES settlements(id) ON DELETE SET NULL;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_accounts_user_id ON accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_accounts_account_type ON accounts(account_type);
CREATE INDEX IF NOT EXISTS idx_account_transactions_account_id ON account_transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_account_transactions_type ON account_transactions(type);
CREATE INDEX IF NOT EXISTS idx_account_transactions_order_id ON account_transactions(order_id);
CREATE INDEX IF NOT EXISTS idx_account_transactions_settlement_id ON account_transactions(settlement_id);
CREATE INDEX IF NOT EXISTS idx_account_transactions_created_at ON account_transactions(created_at);
CREATE INDEX IF NOT EXISTS idx_settlements_payer_account_id ON settlements(payer_account_id);
CREATE INDEX IF NOT EXISTS idx_settlements_receiver_account_id ON settlements(receiver_account_id);
CREATE INDEX IF NOT EXISTS idx_settlements_status ON settlements(status);
CREATE INDEX IF NOT EXISTS idx_settlements_confirmation_code ON settlements(confirmation_code);

-- Enable RLS for financial tables
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE settlements ENABLE ROW LEVEL SECURITY;

-- RLS Policies for accounts table
CREATE POLICY "Users can view own account" ON accounts
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "System can create accounts" ON accounts
  FOR INSERT WITH CHECK (true);

CREATE POLICY "System can update account balance" ON accounts
  FOR UPDATE USING (true);

CREATE POLICY "Admins can view all accounts" ON accounts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- RLS Policies for account_transactions table
CREATE POLICY "Users can view own account transactions" ON account_transactions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM accounts 
      WHERE accounts.id = account_transactions.account_id 
      AND accounts.user_id = auth.uid()
    )
  );

CREATE POLICY "System can create transactions" ON account_transactions
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Admins can view all transactions" ON account_transactions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- RLS Policies for settlements table
CREATE POLICY "Users can view own settlements as payer" ON settlements
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM accounts 
      WHERE accounts.id = settlements.payer_account_id 
      AND accounts.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can view own settlements as receiver" ON settlements
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM accounts 
      WHERE accounts.id = settlements.receiver_account_id 
      AND accounts.user_id = auth.uid()
    )
  );

CREATE POLICY "Delivery agents can create settlements" ON settlements
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM accounts a
      JOIN users u ON u.id = a.user_id
      WHERE a.id = payer_account_id 
      AND a.user_id = auth.uid()
      AND u.role = 'repartidor'
    )
  );

CREATE POLICY "Restaurant owners can update settlements" ON settlements
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM accounts a
      JOIN users u ON u.id = a.user_id
      WHERE a.id = receiver_account_id 
      AND a.user_id = auth.uid()
      AND u.role = 'restaurante'
    )
  );

CREATE POLICY "Admins can manage all settlements" ON settlements
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Add missing columns to existing orders table
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS delivery_fee DECIMAL(10,2) DEFAULT 35.00,
ADD COLUMN IF NOT EXISTS pickup_code TEXT;

-- Add missing user status column if not exists
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS status TEXT CHECK (status IN ('pending', 'approved', 'rejected', 'suspended')) DEFAULT 'pending';

-- Function to create account when user is approved
CREATE OR REPLACE FUNCTION create_account_on_approval()
RETURNS TRIGGER AS $$
BEGIN
  -- Check if user role is restaurant or delivery agent and status changed to approved
  IF NEW.role IN ('restaurante', 'repartidor') AND NEW.status = 'approved' AND 
     (OLD.status IS NULL OR OLD.status != 'approved') THEN
    
    -- Create account for this user
    INSERT INTO accounts (user_id, account_type, balance)
    VALUES (
      NEW.id, 
      CASE 
        WHEN NEW.role = 'restaurante' THEN 'restaurant'
        WHEN NEW.role = 'repartidor' THEN 'delivery_agent'
      END,
      0.00
    )
    ON CONFLICT (user_id) DO NOTHING; -- Avoid duplicate if account already exists
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for account creation
DROP TRIGGER IF EXISTS trigger_create_account_on_approval ON users;
CREATE TRIGGER trigger_create_account_on_approval
  AFTER UPDATE ON users
  FOR EACH ROW
  EXECUTE FUNCTION create_account_on_approval();

-- Function to generate pickup code when order status changes to ready_for_pickup
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

-- Create trigger for pickup code generation
DROP TRIGGER IF EXISTS trigger_generate_pickup_code ON orders;
CREATE TRIGGER trigger_generate_pickup_code
  BEFORE UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION generate_pickup_code();

-- Function to process financial transactions when order is delivered
CREATE OR REPLACE FUNCTION process_order_financial_transactions()
RETURNS TRIGGER AS $$
DECLARE
  restaurant_account_id UUID;
  delivery_account_id UUID;
  product_total DECIMAL(10,2);
  platform_commission DECIMAL(10,2);
  delivery_earning DECIMAL(10,2);
BEGIN
  -- Only process when status changes to 'delivered'
  IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN
    
    -- Get restaurant account
    SELECT a.id INTO restaurant_account_id
    FROM accounts a
    JOIN restaurants r ON r.user_id = a.user_id
    WHERE r.id = NEW.restaurant_id AND a.account_type = 'restaurant';
    
    -- Get delivery agent account
    SELECT a.id INTO delivery_account_id
    FROM accounts a
    WHERE a.user_id = NEW.delivery_agent_id AND a.account_type = 'delivery_agent';
    
    -- Calculate amounts
    product_total := NEW.total_amount - COALESCE(NEW.delivery_fee, 35.00);
    platform_commission := product_total * 0.20;
    delivery_earning := COALESCE(NEW.delivery_fee, 35.00) * 0.85;
    
    -- Create transactions based on payment method
    IF NEW.payment_method = 'cash' THEN
      -- Cash payment: 4 transactions
      
      -- 1. Restaurant revenue (credit)
      INSERT INTO account_transactions (account_id, type, amount, order_id, description)
      VALUES (restaurant_account_id, 'ORDER_REVENUE', product_total, NEW.id, 
              'Revenue from order ' || NEW.id);
      
      -- 2. Platform commission (debit)
      INSERT INTO account_transactions (account_id, type, amount, order_id, description)
      VALUES (restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission, NEW.id, 
              'Platform commission for order ' || NEW.id);
      
      -- 3. Delivery earning (credit)
      INSERT INTO account_transactions (account_id, type, amount, order_id, description)
      VALUES (delivery_account_id, 'DELIVERY_EARNING', delivery_earning, NEW.id, 
              'Delivery earning for order ' || NEW.id);
      
      -- 4. Cash collected (debit)
      INSERT INTO account_transactions (account_id, type, amount, order_id, description)
      VALUES (delivery_account_id, 'CASH_COLLECTED', -NEW.total_amount, NEW.id, 
              'Cash collected for order ' || NEW.id);
      
    ELSE
      -- Card payment: 3 transactions (no cash collection)
      
      -- 1. Restaurant revenue (credit)
      INSERT INTO account_transactions (account_id, type, amount, order_id, description)
      VALUES (restaurant_account_id, 'ORDER_REVENUE', product_total, NEW.id, 
              'Revenue from order ' || NEW.id);
      
      -- 2. Platform commission (debit)
      INSERT INTO account_transactions (account_id, type, amount, order_id, description)
      VALUES (restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission, NEW.id, 
              'Platform commission for order ' || NEW.id);
      
      -- 3. Delivery earning (credit)
      INSERT INTO account_transactions (account_id, type, amount, order_id, description)
      VALUES (delivery_account_id, 'DELIVERY_EARNING', delivery_earning, NEW.id, 
              'Delivery earning for order ' || NEW.id);
    END IF;
    
    -- Update account balances
    UPDATE accounts 
    SET balance = (
      SELECT COALESCE(SUM(amount), 0) 
      FROM account_transactions 
      WHERE account_id = accounts.id
    ),
    updated_at = now()
    WHERE id IN (restaurant_account_id, delivery_account_id);
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for financial processing
DROP TRIGGER IF EXISTS trigger_process_order_financial_transactions ON orders;
CREATE TRIGGER trigger_process_order_financial_transactions
  AFTER UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION process_order_financial_transactions();

-- Function to process settlement completion
CREATE OR REPLACE FUNCTION process_settlement_completion()
RETURNS TRIGGER AS $$
BEGIN
  -- Only process when status changes to 'completed'
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    
    -- Create settlement payment transaction for payer (delivery agent)
    INSERT INTO account_transactions (account_id, type, amount, settlement_id, description)
    VALUES (NEW.payer_account_id, 'SETTLEMENT_PAYMENT', NEW.amount, NEW.id, 
            'Settlement payment: ' || NEW.amount || ' MXN');
    
    -- Create settlement reception transaction for receiver (restaurant)
    INSERT INTO account_transactions (account_id, type, amount, settlement_id, description)
    VALUES (NEW.receiver_account_id, 'SETTLEMENT_RECEPTION', -NEW.amount, NEW.id, 
            'Settlement reception: ' || NEW.amount || ' MXN');
    
    -- Update account balances
    UPDATE accounts 
    SET balance = (
      SELECT COALESCE(SUM(amount), 0) 
      FROM account_transactions 
      WHERE account_id = accounts.id
    ),
    updated_at = now()
    WHERE id IN (NEW.payer_account_id, NEW.receiver_account_id);
    
    -- Set completion timestamp
    NEW.completed_at = now();
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for settlement completion
DROP TRIGGER IF EXISTS trigger_process_settlement_completion ON settlements;
CREATE TRIGGER trigger_process_settlement_completion
  BEFORE UPDATE ON settlements
  FOR EACH ROW
  EXECUTE FUNCTION process_settlement_completion();

-- Function to generate settlement confirmation code
CREATE OR REPLACE FUNCTION generate_settlement_confirmation_code()
RETURNS TRIGGER AS $$
BEGIN
  -- Generate 4-digit confirmation code
  NEW.confirmation_code = LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for settlement code generation
DROP TRIGGER IF EXISTS trigger_generate_settlement_confirmation_code ON settlements;
CREATE TRIGGER trigger_generate_settlement_confirmation_code
  BEFORE INSERT ON settlements
  FOR EACH ROW
  EXECUTE FUNCTION generate_settlement_confirmation_code();