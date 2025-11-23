-- =====================================================
-- RLS: Allow clients to read assigned delivery agent profile (and vice versa)
-- Purpose: Make delivery agent name visible in client tracker without exposing all users
-- This policy permits SELECT on public.users only if:
--  - The current user is the order owner and the row is the assigned delivery agent, OR
--  - The current user is the assigned delivery agent and the row is the order owner, OR
--  - The row is the current user (self, already covered but kept for completeness)
-- =====================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'users' AND policyname = 'users_select_related_in_orders'
  ) THEN
    CREATE POLICY "users_select_related_in_orders" ON public.users
      FOR SELECT
      USING (
        -- Self always allowed (fallback)
        id = auth.uid()
        -- Client can see their assigned delivery agent profile
        OR EXISTS (
          SELECT 1 FROM public.orders o
          WHERE o.user_id = auth.uid()
            AND o.delivery_agent_id = users.id
        )
        -- Delivery agent can see the client profile for orders they are assigned to
        OR EXISTS (
          SELECT 1 FROM public.orders o
          WHERE o.delivery_agent_id = auth.uid()
            AND o.user_id = users.id
        )
      );
  END IF;
END $$;

-- Note: Admins already have full access via existing admin policy.
