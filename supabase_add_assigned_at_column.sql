-- Migration: Add assigned_at column to orders table
-- This migration adds the missing assigned_at column that tracks when a delivery agent was assigned to an order

-- Add the assigned_at column to the orders table
ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMP WITH TIME ZONE;

-- Create an index for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_assigned_at ON public.orders (assigned_at);

-- Add comment for documentation
COMMENT ON COLUMN public.orders.assigned_at IS 'Timestamp when the order was assigned to a delivery agent';

-- Update any existing orders that have delivery_agent_id but no assigned_at
UPDATE public.orders 
SET assigned_at = updated_at 
WHERE delivery_agent_id IS NOT NULL 
  AND assigned_at IS NULL;

-- Verification: Check that the column was added successfully
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'orders' 
  AND column_name = 'assigned_at';

-- Expected output: assigned_at | timestamp with time zone | YES