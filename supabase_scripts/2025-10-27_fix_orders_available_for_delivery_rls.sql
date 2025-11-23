-- =============================================
-- Fix RLS: Allow approved delivery agents to read available orders
-- Context:
--  - Existing base policy only allows: client owner, assigned courier, or restaurant owner
--  - Missing: delivery agents reading UNASSIGNED orders with status 'confirmed'/'in_preparation'/'preparing'/'ready_for_pickup'
--  - Prior script 73_orders_available_for_delivery_policy.sql checked role = 'repartidor'
--    but the canonical role in public.users is 'delivery_agent'. This mismatch blocks access.
--
-- What this script does (idempotent):
--  1) Ensures RLS is enabled on public.orders
--  2) Drops and recreates policy orders_select_available_for_delivery with correct role/status checks
--  3) Optionally (safe) adds a focused policy to read assigned orders for couriers
-- =============================================

DO $$
BEGIN
  -- 1) Ensure RLS is enabled on orders
  EXECUTE 'ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY';

  -- 2) Recreate policy for available orders (unassigned) visible to approved delivery agents
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'orders' AND policyname = 'orders_select_available_for_delivery'
  ) THEN
    EXECUTE 'DROP POLICY "orders_select_available_for_delivery" ON public.orders';
  END IF;

  -- Note: We accept both role names just in case legacy data used "repartidor"
  EXECUTE $policy$
    CREATE POLICY "orders_select_available_for_delivery" ON public.orders
      FOR SELECT USING (
        -- Must be a delivery agent and have an approved delivery profile
        EXISTS (
          SELECT 1
          FROM public.users u
          WHERE u.id = auth.uid()
            AND (u.role = 'delivery_agent' OR u.role = 'repartidor')
        )
        AND EXISTS (
          SELECT 1
          FROM public.delivery_agent_profiles dap
          WHERE dap.user_id = auth.uid()
            AND dap.account_state = 'approved'
        )
        -- Order must be unassigned and in a pickup-eligible status
        AND delivery_agent_id IS NULL
        AND status IN ('confirmed', 'in_preparation', 'ready_for_pickup')
      );
  $policy$;

  -- 3) Safety: ensure a minimal policy exists for assigned orders (harmless if you already have a broader one)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'orders' AND policyname = 'orders_select_assigned_to_delivery'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "orders_select_assigned_to_delivery" ON public.orders
        FOR SELECT USING (delivery_agent_id = auth.uid());
    $policy$;
  END IF;
END $$;

-- Quick verification queries (run manually in SQL editor):
--  -- As a delivery agent (approved):
--  SELECT id, status, delivery_agent_id FROM public.orders
--   WHERE delivery_agent_id IS NULL AND status IN ('confirmed','in_preparation','preparing','ready_for_pickup')
--   ORDER BY created_at DESC LIMIT 20;
--
--  -- As the same agent, your assigned orders still visible:
--  SELECT id, status FROM public.orders WHERE delivery_agent_id = auth.uid() ORDER BY created_at DESC LIMIT 20;
