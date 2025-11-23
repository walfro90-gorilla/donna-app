-- Fix: Ensure delivery-agent signups set role correctly and create profile automatically
-- Idempotent: safe to run multiple times

-- 1) Helper function: set role to 'delivery_agent' and create minimal profile
CREATE OR REPLACE FUNCTION public.ensure_delivery_agent_role_and_profile(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
BEGIN
  -- Update role only if different
  UPDATE public.users u
  SET role = 'delivery_agent'
  WHERE u.id = p_user_id AND COALESCE(u.role, '') <> 'delivery_agent';

  -- Ensure delivery profile exists (minimal stub)
  INSERT INTO public.delivery_agent_profiles (
    user_id,
    status,
    account_state,
    created_at,
    updated_at
  )
  VALUES (
    p_user_id,
    'pending',
    'pending_verification',
    v_now,
    v_now
  )
  ON CONFLICT (user_id) DO NOTHING;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_delivery_agent_role_and_profile(uuid) TO anon, authenticated, service_role;

-- 2) Trigger function: react to accounts inserts for delivery_agent account_type
CREATE OR REPLACE FUNCTION public.handle_delivery_agent_account_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.account_type = 'delivery_agent' THEN
    PERFORM public.ensure_delivery_agent_role_and_profile(NEW.user_id);
  END IF;
  RETURN NEW;
END;
$$;

-- 3) Attach triggers (insert + account_type change to delivery_agent)
DROP TRIGGER IF EXISTS trg_handle_delivery_agent_account_insert ON public.accounts;
CREATE TRIGGER trg_handle_delivery_agent_account_insert
AFTER INSERT ON public.accounts
FOR EACH ROW
EXECUTE FUNCTION public.handle_delivery_agent_account_insert();

DROP TRIGGER IF EXISTS trg_handle_delivery_agent_account_update ON public.accounts;
CREATE TRIGGER trg_handle_delivery_agent_account_update
AFTER UPDATE OF account_type ON public.accounts
FOR EACH ROW
WHEN (NEW.account_type = 'delivery_agent' AND COALESCE(OLD.account_type, '') <> 'delivery_agent')
EXECUTE FUNCTION public.handle_delivery_agent_account_insert();

-- 4) Optional one-time backfill for existing records
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT a.user_id
    FROM public.accounts a
    LEFT JOIN public.users u ON u.id = a.user_id
    LEFT JOIN public.delivery_agent_profiles p ON p.user_id = a.user_id
    WHERE a.account_type = 'delivery_agent'
      AND (u.role IS DISTINCT FROM 'delivery_agent' OR p.user_id IS NULL)
  LOOP
    PERFORM public.ensure_delivery_agent_role_and_profile(r.user_id);
  END LOOP;
END $$;
