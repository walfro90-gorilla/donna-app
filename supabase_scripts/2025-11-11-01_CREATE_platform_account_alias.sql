-- Purpose: Ensure a generic 'platform' account exists for RPCs that search it
-- Context: Your DB currently has 'platform_revenue' and 'platform_payables'
--          but some flows expect an account_type = 'platform'.
--          This script creates that alias account in a surgical, idempotent way.

DO $$
DECLARE
  v_exists boolean;
  v_platform_user uuid;
BEGIN
  -- Use only the real schema
  PERFORM set_config('search_path', 'public, extensions', true);

  -- If already present, do nothing
  SELECT EXISTS (
    SELECT 1 FROM public.accounts WHERE account_type = 'platform'
  ) INTO v_exists;

  IF v_exists THEN
    RAISE NOTICE '✅ platform account already exists – nothing to do';
    RETURN;
  END IF;

  -- Reuse the user_id from an existing platform account (payables preferred, then revenue)
  SELECT user_id
  INTO v_platform_user
  FROM public.accounts
  WHERE account_type IN ('platform_payables', 'platform_revenue')
    AND user_id IS NOT NULL
  ORDER BY CASE account_type WHEN 'platform_payables' THEN 0 ELSE 1 END,
           created_at ASC
  LIMIT 1;

  IF v_platform_user IS NULL THEN
    RAISE EXCEPTION '❌ No se encontró user_id base para plataforma (platform_payables/platform_revenue)';
  END IF;

  -- Create the alias account (defaults handle status/updated_at if present)
  INSERT INTO public.accounts (user_id, account_type, balance)
  VALUES (v_platform_user, 'platform', 0.00);

  RAISE NOTICE '✅ platform account created successfully (type=platform, user_id=%).', v_platform_user;
END $$;
