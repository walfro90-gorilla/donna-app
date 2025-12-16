-- Add status field to users table for approval workflow
-- This allows admins to approve delivery agents before they can receive orders

-- Add status column to users table
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS status TEXT 
CHECK (status IN ('pending', 'approved', 'rejected', 'suspended')) 
DEFAULT 'pending';

-- Update existing users to have appropriate status
-- Set existing admins and regular users to approved
UPDATE users 
SET status = 'approved' 
WHERE role IN ('admin', 'cliente', 'restaurante');

-- Set delivery agents to pending if they don't have status
UPDATE users 
SET status = 'pending' 
WHERE role = 'repartidor' AND status IS NULL;

-- Create index for efficient queries
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);

-- Update RLS policies to include status checks for delivery agents
-- Drop existing delivery agent policies that might conflict
DROP POLICY IF EXISTS "Delivery agents can view available orders" ON orders;
DROP POLICY IF EXISTS "Delivery agents can view assigned orders" ON orders;
DROP POLICY IF EXISTS "Delivery agents can update assigned orders" ON orders;

-- Recreate delivery agent policies with status requirement
CREATE POLICY "Delivery agents can view available orders" ON orders
  FOR SELECT USING (
    status = 'in_preparation' AND 
    delivery_agent_id IS NULL AND
    EXISTS (
      SELECT 1 FROM users 
      WHERE id = auth.uid() 
      AND role = 'repartidor' 
      AND status = 'approved'
      AND is_active = true
    )
  );

CREATE POLICY "Delivery agents can view assigned orders" ON orders
  FOR SELECT USING (
    delivery_agent_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM users 
      WHERE id = auth.uid() 
      AND status = 'approved'
    )
  );

CREATE POLICY "Delivery agents can update assigned orders" ON orders
  FOR UPDATE USING (
    delivery_agent_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM users 
      WHERE id = auth.uid() 
      AND status = 'approved'
    )
  );

-- Add policy to allow users to see their own status
CREATE POLICY IF NOT EXISTS "Users can view own status" ON users
  FOR SELECT USING (auth.uid() = id);