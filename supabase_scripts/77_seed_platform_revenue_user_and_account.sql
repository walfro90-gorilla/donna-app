-- =====================================================
-- Seed: Platform Revenue master user and account
-- Compatible with existing functions that lookup by email and expect
-- account_type = 'restaurant' for the platform revenue sink.
-- Idempotent and safe to re-run.
-- =====================================================

DO $$
DECLARE
  v_email TEXT := 'platform+revenue@doarepartos.com';
  v_name  TEXT := 'Plataforma - Ingresos';
  v_role  TEXT := 'platform';
  v_user_id UUID;
  v_account_id UUID;
BEGIN
  -- 1) Ensure auth user exists (prefer SQL function auth.create_user if available)
  SELECT id INTO v_user_id FROM auth.users WHERE email = v_email;

  IF v_user_id IS NULL THEN
    BEGIN
      -- Create with random password, email confirmed
      SELECT (auth.create_user(
        email := v_email,
        password := encode(gen_random_bytes(16), 'hex'),
        email_confirm := true,
        user_metadata := jsonb_build_object('name', v_name, 'system', true, 'role', v_role)
      )).id INTO v_user_id;
      RAISE NOTICE '✅ Created auth user for % with id %', v_email, v_user_id;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE EXCEPTION '❌ Cannot create auth user for %: %', v_email, SQLERRM;
    END;
  ELSE
    RAISE NOTICE 'ℹ️ Auth user already exists: %', v_user_id;
  END IF;

  -- 2) Ensure public.users profile exists
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_user_id) THEN
    IF EXISTS (
      SELECT 1
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE p.proname = 'create_user_profile_public' AND n.nspname = 'public'
    ) THEN
      PERFORM public.create_user_profile_public(
        v_user_id,
        v_email,
        v_name,
        NULL,    -- phone
        NULL,    -- address
        v_role,  -- role
        NULL, NULL, NULL -- lat, lon, address_structured
      );
      RAISE NOTICE '✅ Inserted public.users via RPC create_user_profile_public';
    ELSE
      -- Fallback: direct insert with a conservative column set
      INSERT INTO public.users (
        id, email, name, role, created_at, updated_at
      ) VALUES (
        v_user_id, v_email, v_name, v_role, NOW(), NOW()
      );
      RAISE NOTICE '✅ Inserted public.users directly (fallback)';
    END IF;
  ELSE
    RAISE NOTICE 'ℹ️ public.users profile already exists for %', v_email;
  END IF;

  -- 3) Ensure a financial account exists for this user as 'restaurant'
  --    This matches legacy functions that expect platform revenue under 'restaurant'.
  SELECT id INTO v_account_id
  FROM public.accounts
  WHERE user_id = v_user_id AND account_type = 'restaurant'
  LIMIT 1;

  IF v_account_id IS NULL THEN
    INSERT INTO public.accounts (
      id, user_id, account_type, balance, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), v_user_id, 'restaurant', 0.0, NOW(), NOW()
    )
    RETURNING id INTO v_account_id;
    RAISE NOTICE '✅ Created platform revenue account id=% for user %', v_account_id, v_email;
  ELSE
    RAISE NOTICE 'ℹ️ Platform revenue account already exists id=% for user %', v_account_id, v_email;
  END IF;

END $$;

-- === Verification query ===
SELECT
  u.id          AS user_id,
  u.email       AS user_email,
  u.name        AS user_name,
  u.role        AS user_role,
  a.id          AS account_id,
  a.account_type,
  a.balance
FROM public.users u
LEFT JOIN public.accounts a
  ON a.user_id = u.id AND a.account_type = 'restaurant'
WHERE u.email = 'platform+revenue@doarepartos.com';
