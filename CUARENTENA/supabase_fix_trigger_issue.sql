-- Temporary fix for trigger function error during order creation
-- This script will disable problematic triggers temporarily

-- First, let's see what triggers exist on the orders table
SELECT 
    trigger_name, 
    event_manipulation, 
    action_timing, 
    action_statement 
FROM information_schema.triggers 
WHERE event_object_table = 'orders';

-- Let's also check what functions exist that might be called
SELECT 
    routine_name,
    routine_definition
FROM information_schema.routines 
WHERE routine_name LIKE '%order%' OR routine_name LIKE '%pickup%' OR routine_name LIKE '%financial%';

-- Disable all triggers on orders table temporarily
ALTER TABLE orders DISABLE TRIGGER ALL;

-- Alternative: Drop specific problematic triggers if identified
-- DROP TRIGGER IF EXISTS trigger_process_order_financial_transactions ON orders;
-- DROP TRIGGER IF EXISTS trigger_generate_pickup_code ON orders;

-- Re-create only the necessary trigger for pickup code generation
-- (This one should be safe as it only modifies the NEW record)
CREATE OR REPLACE FUNCTION generate_pickup_code_safe()
RETURNS TRIGGER AS $$
BEGIN
  -- Only generate pickup code on INSERT with ready_for_pickup status
  -- or UPDATE to ready_for_pickup status
  IF NEW.status = 'ready_for_pickup' AND 
     (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND (OLD.status IS NULL OR OLD.status != 'ready_for_pickup'))) THEN
    NEW.pickup_code = LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create safe trigger for pickup code generation (BEFORE operations only)
DROP TRIGGER IF EXISTS trigger_generate_pickup_code_safe ON orders;
CREATE TRIGGER trigger_generate_pickup_code_safe
  BEFORE INSERT OR UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION generate_pickup_code_safe();