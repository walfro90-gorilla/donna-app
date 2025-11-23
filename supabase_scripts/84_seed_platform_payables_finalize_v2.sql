-- =============================================================
-- Seed/Ensure Platform Payables user and financial account (v2)
-- - Handles CHECK constraint on accounts.account_type gracefully
-- - Idempotent and safe to run multiple times
-- - Assumes the Auth user exists (created manually in Supabase Auth)
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
  v_has_account boolean;
BEGIN
  -- 1) Resolve user id from public.users or auth.users
  SELECT id INTO v_user_id FROM public.users WHERE email = v_email;
  IF v_user_id IS NULL THEN
    SELECT id INTO v_user_id FROM auth.users WHERE email = v_email;
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Could not ensure auth user for %; create it via Auth Admin and re-run.', v_email;
  END IF;

  -- 2) Ensure a profile row exists in public.users (minimal columns only)
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_user_id) THEN
    INSERT INTO public.users (id, email, name)
    VALUES (v_user_id, v_email, v_name);
  ELSE
    UPDATE public.users SET email = v_email, name = v_name
    WHERE id = v_user_id;
  END IF;

  -- Optional columns if present
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='users' AND column_name='role'
  ) INTO v_has_role;
  IF v_has_role THEN
    UPDATE public.users SET role = v_role WHERE id = v_user_id;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='users' AND column_name='status'
  ) INTO v_has_status;
  IF v_has_status THEN
    UPDATE public.users SET status = 'approved' WHERE id = v_user_id;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='users' AND column_name='email_verified'
  ) INTO v_has_email_verified;
  IF v_has_email_verified THEN
    UPDATE public.users SET email_verified = true WHERE id = v_user_id;
  END IF;

  -- 3) Ensure a financial account exists for this user.
  -- Try preferred type 'platform_payables'; if the CHECK constraint blocks it,
  -- fallback to a known-allowed type (prefer 'restaurant', else 'delivery_agent', else 'platform').
  SELECT EXISTS (SELECT 1 FROM public.accounts WHERE user_id = v_user_id) INTO v_has_account;

  IF NOT v_has_account THEN
    BEGIN
      -- First attempt: platform_payables
      INSERT INTO public.accounts (user_id, account_type, balance)
      VALUES (v_user_id, 'platform_payables', 0.00);
    EXCEPTION
      WHEN check_violation THEN
        -- Fallback 1: restaurant (most functions already support this)
        IF EXISTS (
          SELECT 1 FROM information_schema.check_constraints
          WHERE constraint_schema = 'public' 
            AND constraint_name = 'accounts_account_type_check'
            AND check_clause ILIKE '%restaurant%'
        ) THEN
          INSERT INTO public.accounts (user_id, account_type, balance)
          VALUES (v_user_id, 'restaurant', 0.00);
        ELSIF EXISTS (
          SELECT 1 FROM information_schema.check_constraints
          WHERE constraint_schema = 'public' 
            AND constraint_name = 'accounts_account_type_check'
            AND check_clause ILIKE '%delivery_agent%'
        ) THEN
          -- Fallback 2: delivery_agent
          INSERT INTO public.accounts (user_id, account_type, balance)
          VALUES (v_user_id, 'delivery_agent', 0.00);
        ELSE
          -- Fallback 3: platform (if defined in CHECK)
          BEGIN
            INSERT INTO public.accounts (user_id, account_type, balance)
            VALUES (v_user_id, 'platform', 0.00);
          EXCEPTION WHEN check_violation THEN
            RAISE EXCEPTION 'accounts.account_type CHECK constraint does not allow platform_payables, restaurant, delivery_agent or platform. Please add an allowed type or adjust the constraint.';
          END;
        END IF;
    END;
  END IF;

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
