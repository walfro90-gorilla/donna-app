-- ============================================================================
-- MIGRATION: Add 'not_delivered' status to orders table constraint
-- ============================================================================
-- Date: 2025-01-16
-- Purpose: Allow 'not_delivered' status for orders that couldn't be delivered
-- ============================================================================

-- Step 1: Drop the existing constraint
ALTER TABLE public.orders 
  DROP CONSTRAINT IF EXISTS orders_status_check_final;

-- Step 2: Add the new constraint with 'not_delivered' included
ALTER TABLE public.orders 
  ADD CONSTRAINT orders_status_check_final 
  CHECK (
    status = ANY (
      ARRAY[
        'pending'::text, 
        'confirmed'::text, 
        'preparing'::text, 
        'in_preparation'::text, 
        'ready_for_pickup'::text, 
        'assigned'::text, 
        'picked_up'::text, 
        'on_the_way'::text, 
        'in_transit'::text, 
        'delivered'::text, 
        'cancelled'::text, 
        'canceled'::text,
        'not_delivered'::text  -- ✅ NEW STATUS ADDED
      ]
    )
  );

-- Step 3: Verify the constraint was updated
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 
    FROM pg_constraint 
    WHERE conname = 'orders_status_check_final'
  ) THEN
    RAISE NOTICE '✅ Constraint orders_status_check_final updated successfully';
  ELSE
    RAISE EXCEPTION '❌ Failed to update constraint orders_status_check_final';
  END IF;
END $$;
