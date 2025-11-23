-- =====================================================
-- Seed platform revenue master user and account (doarepartos.com)
-- Fixes error: "Platform revenue account not found for email=platform+revenue@doarepartos.com"
-- Some financial functions look up this specific email to credit commissions.
-- =====================================================

DO $$
DECLARE
  v_user_id uuid;
BEGIN
  -- 1) Ensure platform revenue user exists in public.users
  SELECT id INTO v_user_id FROM public.users WHERE email = 'platform+revenue@doarepartos.com';

  IF v_user_id IS NULL THEN
    INSERT INTO public.users (id, email, name, role, status, email_confirm, created_at)
    VALUES (
      gen_random_uuid(),
      'platform+revenue@doarepartos.com',
      'Plataforma - Ingresos',
      'admin',                -- role allowed by policies; not used for login
      'approved',
      true,
      NOW()
    ) RETURNING id INTO v_user_id;
  END IF;

  -- 2) Ensure a financial account exists for this user
  -- Some existing functions expect account_type = 'restaurant' for platform revenue sink
  IF NOT EXISTS (
    SELECT 1 FROM public.accounts 
    WHERE user_id = v_user_id AND account_type = 'restaurant'
  ) THEN
    INSERT INTO public.accounts (user_id, account_type, balance, status, created_at)
    VALUES (v_user_id, 'restaurant', 0.00, 'active', NOW());
  END IF;
END $$;

-- Optional: If your setup also uses a platform payables account, seed similarly.
-- Keep separate to avoid conflicts with environments that don't use it yet.
