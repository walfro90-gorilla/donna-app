-- =============================================================
-- Seed/Ensure Platform Payables user and financial account
-- Fixes error:
--   "Platform payables account not found for email=platform+payables@doarepartos.com"
--
-- This script assumes you will create the Auth user manually in Supabase Auth
-- with the email below. Then run this script to ensure the public.users profile
-- and the financial account in public.accounts.
--
-- The script is idempotent and safe to run multiple times.
-- =============================================================

DO $$
DECLARE
  v_email       text := 'platform+payables@doarepartos.com';
  v_name        text := 'Plataforma - Pagos/Flotante';
  v_role        text := 'platform';
  v_user_id     uuid;
  v_has_role    boolean;
  v_has_status  boolean;
  v_has_email_verified boolean;
BEGIN
  -- Try to find the user in public.users
  SELECT id INTO v_user_id FROM public.users WHERE email = v_email;

  -- If not present, try to find in auth.users (created manually in Auth)
  IF v_user_id IS NULL THEN
    SELECT id INTO v_user_id FROM auth.users WHERE email = v_email;
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Could not ensure auth user for %; create it via Auth Admin and re-run.', v_email;
  END IF;

  -- Detect optional columns in public.users
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='users' AND column_name='role'
  ) INTO v_has_role;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='users' AND column_name='status'
  ) INTO v_has_status;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='users' AND column_name='email_verified'
  ) INTO v_has_email_verified;

  -- Ensure row in public.users (insert minimal columns if missing)
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_user_id) THEN
    INSERT INTO public.users (id, email, name)
    VALUES (v_user_id, v_email, v_name);
  ELSE
    -- Update email/name to keep them consistent
    UPDATE public.users SET email = v_email, name = v_name
    WHERE id = v_user_id;
  END IF;

  -- Optional updates depending on schema
  IF v_has_role THEN
    UPDATE public.users SET role = v_role WHERE id = v_user_id;
  END IF;
  IF v_has_status THEN
    UPDATE public.users SET status = 'approved' WHERE id = v_user_id;
  END IF;
  IF v_has_email_verified THEN
    UPDATE public.users SET email_verified = true WHERE id = v_user_id;
  END IF;

  -- Ensure financial account exists with a distinct account_type
  -- Prefer account_type = 'platform_payables' to align with accounting logic
  INSERT INTO public.accounts (user_id, account_type, balance)
  VALUES (v_user_id, 'platform_payables', 0.00)
  ON CONFLICT (user_id) DO NOTHING;

  -- If account exists but with a different type, normalize it
  UPDATE public.accounts SET account_type = 'platform_payables'
  WHERE user_id = v_user_id AND (account_type IS NULL OR account_type <> 'platform_payables');

  RAISE NOTICE '✅ Ensured platform payables user (id=%) and financial account', v_user_id;
END;
$$;

-- Quick verification
SELECT 
  u.email,
  u.name,
  a.id  AS account_id,
  a.account_type,
  a.balance,
  a.created_at,
  a.updated_at
FROM public.users u
LEFT JOIN public.accounts a ON a.user_id = u.id
WHERE u.email = 'platform+payables@doarepartos.com';
