-- Check the current structure of order_items table
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'order_items' 
ORDER BY ordinal_position;

-- Also check if we have any existing data
SELECT COUNT(*) as total_rows FROM order_items;