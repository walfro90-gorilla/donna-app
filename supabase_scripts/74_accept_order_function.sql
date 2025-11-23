-- ================================================
-- accept_order RPC
-- ================================================
-- Atomically assigns the current authenticated delivery agent to an order
-- and sets status to 'assigned' only if the order is still available.
-- Also writes a row into order_status_updates.
-- SECURITY DEFINER so it bypasses RLS safely while enforcing conditions here.
-- ================================================

DROP FUNCTION IF EXISTS accept_order(uuid);

CREATE OR REPLACE FUNCTION accept_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_updated boolean := false;
BEGIN
  -- Ensure there is an authenticated user
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Not authenticated');
  END IF;

  -- Assign the order if still available
  UPDATE public.orders o
  SET 
    delivery_agent_id = v_user_id,
    assigned_at = NOW(),
    status = 'assigned',
    updated_at = NOW()
  WHERE o.id = p_order_id
    AND o.delivery_agent_id IS NULL
    AND o.status IN ('confirmed','in_preparation','ready_for_pickup')
  RETURNING TRUE INTO v_updated;

  IF NOT v_updated THEN
    RETURN jsonb_build_object('success', false, 'message', 'Order not available');
  END IF;

  -- Track status change
  BEGIN
    INSERT INTO public.order_status_updates (
      order_id,
      status,
      actor_role,
      actor_id,
      updated_by_user_id,
      created_at
    ) VALUES (
      p_order_id,
      'assigned',
      'repartidor',
      v_user_id,
      v_user_id,
      NOW()
    );
  EXCEPTION WHEN others THEN
    -- Do not fail the main action for tracking errors
    NULL;
  END;

  RETURN jsonb_build_object('success', true, 'message', 'Order assigned');
END;
$$;

GRANT EXECUTE ON FUNCTION accept_order(uuid) TO authenticated;

COMMENT ON FUNCTION accept_order IS 'Assigns available order to current delivery agent and marks it as assigned.';
