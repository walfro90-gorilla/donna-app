-- RPC: rpc_get_platform_account_id
-- Returns the UUID for the platform account used in settlements.
-- Preference order: 'platform' → 'platform_payables' → 'platform_revenue'

CREATE OR REPLACE FUNCTION public.rpc_get_platform_account_id()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_id uuid;
BEGIN
  -- 1) Generic 'platform'
  SELECT id INTO v_id
  FROM public.accounts
  WHERE account_type = 'platform'
  ORDER BY created_at ASC
  LIMIT 1;

  -- 2) Fallback to platform_payables
  IF v_id IS NULL THEN
    SELECT id INTO v_id
    FROM public.accounts
    WHERE account_type = 'platform_payables'
    ORDER BY created_at ASC
    LIMIT 1;
  END IF;

  -- 3) Fallback to platform_revenue
  IF v_id IS NULL THEN
    SELECT id INTO v_id
    FROM public.accounts
    WHERE account_type = 'platform_revenue'
    ORDER BY created_at ASC
    LIMIT 1;
  END IF;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'No se encontró cuenta de plataforma';
  END IF;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_platform_account_id() TO anon, authenticated, service_role;
