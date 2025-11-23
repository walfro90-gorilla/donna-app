-- ================================================
-- Admin Approval Function for Delivery Agents
-- ================================================
-- When admin approves a delivery agent:
-- 1. account_state changes from 'pending' to 'approved'
-- 2. status changes to 'offline' (ready to go online)
-- ================================================

-- Drop existing function if any
DROP FUNCTION IF EXISTS approve_delivery_agent(uuid);
DROP FUNCTION IF EXISTS admin_approve_delivery_agent(uuid);

-- Create function with SECURITY DEFINER to bypass RLS
CREATE OR REPLACE FUNCTION admin_approve_delivery_agent(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Update delivery_agent_profiles
  UPDATE delivery_agent_profiles
  SET 
    account_state = 'approved',
    status = 'offline',
    updated_at = NOW()
  WHERE user_id = p_user_id;

  -- Check if update was successful
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Delivery agent profile not found'
    );
  END IF;

  -- Return success with updated data
  SELECT jsonb_build_object(
    'success', true,
    'message', 'Delivery agent approved successfully',
    'account_state', account_state,
    'status', status,
    'updated_at', updated_at
  )
  INTO v_result
  FROM delivery_agent_profiles
  WHERE user_id = p_user_id;

  RETURN v_result;
END;
$$;

-- Grant execute permission to authenticated users (admin will check in app)
GRANT EXECUTE ON FUNCTION admin_approve_delivery_agent(uuid) TO authenticated;

-- Add comment
COMMENT ON FUNCTION admin_approve_delivery_agent IS 
'Approves a delivery agent by setting account_state=approved and status=offline. Used by admin panel.';
