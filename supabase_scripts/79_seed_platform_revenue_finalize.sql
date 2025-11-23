-- =====================================================
-- Seed (finalize): Ensure Platform Revenue profile and account exist
-- Context: Auth user will be created manually in Supabase Auth
-- Email used by financial functions: platform+revenue@doarepartos.com
-- Idempotent and safe to re-run.
-- =====================================================

DO $$
DECLARE
  v_email     TEXT := 'platform+revenue@doarepartos.com';
  v_name      TEXT := 'Plataforma - Ingresos';
  v_role      TEXT := 'platform';
  v_user_id   UUID;
  v_account_id UUID;
BEGIN
  -- 1) Require existing auth user (created manually per your note)
  SELECT id INTO v_user_id FROM auth.users WHERE email = v_email;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Auth user % not found in auth.users. Create it via Auth and re-run.', v_email;
  END IF;

  -- 2) Ensure public.users profile exists (minimal columns set, compatible with your schema)
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_user_id) THEN
    INSERT INTO public.users (id, email, name, role, created_at, updated_at)
    VALUES (v_user_id, v_email, v_name, v_role, NOW(), NOW());
    RAISE NOTICE '✅ Inserted public.users profile for %', v_email;
  ELSE
    -- Keep data in sync if email/name are empty
    UPDATE public.users
      SET email = COALESCE(NULLIF(email, ''), v_email),
          name  = COALESCE(NULLIF(name,  ''), v_name),
          role  = COALESCE(NULLIF(role,  ''), v_role),
          updated_at = NOW()
      WHERE id = v_user_id;
    RAISE NOTICE 'ℹ️ public.users profile already exists for % (updated minimal fields if empty)', v_email;
  END IF;

  -- 3) Ensure platform revenue account exists under account_type='restaurant'
  --    This aligns with existing financial functions expecting this mapping.
  SELECT id INTO v_account_id
  FROM public.accounts
  WHERE user_id = v_user_id AND account_type = 'restaurant'
  LIMIT 1;

  IF v_account_id IS NULL THEN
    INSERT INTO public.accounts (id, user_id, account_type, balance, created_at, updated_at)
    VALUES (gen_random_uuid(), v_user_id, 'restaurant', 0.0, NOW(), NOW())
    RETURNING id INTO v_account_id;
    RAISE NOTICE '✅ Created platform revenue account id=% for %', v_account_id, v_email;
  ELSE
    RAISE NOTICE 'ℹ️ Platform revenue account already exists id=% for %', v_account_id, v_email;
  END IF;

  RAISE NOTICE '🎯 Ready: user_id=% account_id=% for %', v_user_id, v_account_id, v_email;
END $$;

-- === Quick verification ===
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
