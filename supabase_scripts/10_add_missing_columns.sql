-- Add missing columns to order_items table
ALTER TABLE order_items 
ADD COLUMN IF NOT EXISTS unit_price DECIMAL(10,2) NOT NULL DEFAULT 0.00;

-- Also add other potentially missing columns
ALTER TABLE order_items 
ADD COLUMN IF NOT EXISTS price DECIMAL(10,2);

-- Update existing rows if any (set unit_price = price if price exists)
UPDATE order_items 
SET unit_price = COALESCE(price, 0.00) 
WHERE unit_price IS NULL OR unit_price = 0;

-- Verify the schema after changes
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'order_items' 
ORDER BY ordinal_position;