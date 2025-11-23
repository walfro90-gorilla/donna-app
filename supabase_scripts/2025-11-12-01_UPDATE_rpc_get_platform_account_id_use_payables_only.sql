-- Purpose: Make the platform account resolution explicit to platform_payables
-- Context: You requested NOT to create/use a generic 'platform' account.
-- Result: rpc_get_platform_account_id() returns ONLY the 'platform_payables' account id.

CREATE OR REPLACE FUNCTION public.rpc_get_platform_account_id()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_id uuid;
BEGIN
  -- Return the unique platform_payables account
  SELECT id INTO v_id
  FROM public.accounts
  WHERE account_type = 'platform_payables'
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'No se encontró cuenta de plataforma (se requiere account_type=platform_payables)';
  END IF;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_platform_account_id() TO anon, authenticated, service_role;
