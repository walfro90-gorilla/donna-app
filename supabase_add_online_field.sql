-- Add 'online' field to restaurants table
-- This field will track if the restaurant is currently active/online

-- Add the online column with default FALSE
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS online BOOLEAN DEFAULT FALSE;

-- Add index for better query performance
CREATE INDEX IF NOT EXISTS idx_restaurants_online ON restaurants(online);

-- Update the RLS policy to include online field for customers
-- Drop the existing policy and recreate it with the online filter
DROP POLICY IF EXISTS "Customers can view approved restaurants" ON restaurants;

CREATE POLICY "Customers can view approved restaurants" ON restaurants
  FOR SELECT USING (status = 'approved' AND online = true);

-- Note: Restaurant owners and admins can still see all restaurants regardless of online status