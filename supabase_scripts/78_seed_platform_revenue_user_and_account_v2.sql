-- =====================================================================
-- Seed platform revenue master user and account (doarepartos.com)
-- Version: v2 (avoids ambiguous RPC by inserting profile directly)
-- Safe to run multiple times (idempotent)
--
-- Fixes prior error:
--   ERROR: function public.create_user_profile_public(...) is not unique
-- by not calling that overloaded RPC and instead writing to public.users
-- with guarded, column-aware inserts.
--
-- What this script does:
-- 1) Ensures auth user exists for email platform+revenue@doarepartos.com
-- 2) Ensures a profile row exists in public.users for that auth user
-- 3) Ensures a financial account exists in public.accounts linked to it
--
-- Notes:
-- - We feature-detect columns (full_name/name/display_name, role, type, currency)
--   so it fits slightly different schemas without failing.
-- - No passwords are created; email is marked confirmed (when possible).
-- - If your project requires additional mandatory columns in public.users or
--   public.accounts, update the dynamic insert segment accordingly.
-- =====================================================================

DO $$
DECLARE
  v_email     text := 'platform+revenue@doarepartos.com';
  v_name      text := 'Plataforma - Ingresos';
  v_role      text := 'platform';
  v_user_id   uuid;
  v_profile_exists boolean := false;

  -- public.users column flags
  has_full_name boolean;
  has_name_col  boolean;
  has_display_name boolean;
  has_role_col  boolean;

  -- public.accounts column flags
  has_type_col boolean;
  has_currency_col boolean;

  v_sql text;
  v_exists_account boolean := false;
BEGIN
  -- 1) Ensure auth user exists
  SELECT id INTO v_user_id FROM auth.users WHERE email = v_email;

  IF v_user_id IS NULL THEN
    BEGIN
      -- Prefer JSONB signature to avoid overloads; confirms email.
      PERFORM auth.create_user(
        jsonb_build_object('email', v_email, 'email_confirm', true)
      );
    EXCEPTION WHEN others THEN
      RAISE NOTICE 'auth.create_user failed or unavailable: %', SQLERRM;
    END;

    SELECT id INTO v_user_id FROM auth.users WHERE email = v_email;
    IF v_user_id IS NULL THEN
      RAISE EXCEPTION 'Could not ensure auth user for %; create it via Auth Admin and re-run.', v_email;
    END IF;
  END IF;

  -- 2) Ensure profile in public.users (avoid ambiguous RPC; write directly)
  SELECT EXISTS(
    SELECT 1 FROM public.users WHERE id = v_user_id
  ) INTO v_profile_exists;

  IF NOT v_profile_exists THEN
    -- Discover available columns on public.users
    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='users' AND column_name='full_name'
    ) INTO has_full_name;

    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='users' AND column_name='name'
    ) INTO has_name_col;

    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='users' AND column_name='display_name'
    ) INTO has_display_name;

    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='users' AND column_name='role'
    ) INTO has_role_col;

    -- Build a column-aware INSERT ... ON CONFLICT DO NOTHING
    v_sql := 'INSERT INTO public.users(id, email';
    IF has_full_name THEN
      v_sql := v_sql || ', full_name';
    ELSIF has_name_col THEN
      v_sql := v_sql || ', name';
    ELSIF has_display_name THEN
      v_sql := v_sql || ', display_name';
    END IF;
    IF has_role_col THEN
      v_sql := v_sql || ', role';
    END IF;
    v_sql := v_sql || ') VALUES ($1, $2';
    IF has_full_name OR has_name_col OR has_display_name THEN
      v_sql := v_sql || ', $3';
    END IF;
    IF has_role_col THEN
      v_sql := v_sql || ', $4';
    END IF;
    v_sql := v_sql || ') ON CONFLICT (id) DO NOTHING';

    IF has_full_name OR has_name_col OR has_display_name THEN
      IF has_role_col THEN
        EXECUTE v_sql USING v_user_id, v_email, v_name, v_role;
      ELSE
        EXECUTE v_sql USING v_user_id, v_email, v_name;
      END IF;
    ELSE
      IF has_role_col THEN
        EXECUTE v_sql USING v_user_id, v_email, v_role; -- here $3 is role
      ELSE
        EXECUTE v_sql USING v_user_id, v_email;
      END IF;
    END IF;
  END IF;

  -- 3) Ensure account in public.accounts
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='accounts' AND column_name='type'
  ) INTO has_type_col;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='accounts' AND column_name='currency'
  ) INTO has_currency_col;

  -- Detect if an account already exists for this user (prefer type if available)
  IF has_type_col THEN
    SELECT EXISTS (
      SELECT 1 FROM public.accounts a
      WHERE a.user_id = v_user_id AND a.type IN ('PLATFORM_REVENUE','MASTER','SYSTEM','REVENUE')
    ) INTO v_exists_account;
  ELSE
    SELECT EXISTS (
      SELECT 1 FROM public.accounts a
      WHERE a.user_id = v_user_id
    ) INTO v_exists_account;
  END IF;

  IF NOT v_exists_account THEN
    v_sql := 'INSERT INTO public.accounts(user_id, name';
    IF has_type_col THEN
      v_sql := v_sql || ', type';
    END IF;
    IF has_currency_col THEN
      v_sql := v_sql || ', currency';
    END IF;
    v_sql := v_sql || ') VALUES ($1, $2';
    IF has_type_col THEN
      v_sql := v_sql || ', $3';
    END IF;
    IF has_currency_col THEN
      IF has_type_col THEN
        v_sql := v_sql || ', $4';
      ELSE
        v_sql := v_sql || ', $3';
      END IF;
    END IF;
    v_sql := v_sql || ')';

    IF has_type_col AND has_currency_col THEN
      EXECUTE v_sql USING v_user_id, 'Cuenta Plataforma - Ingresos', 'PLATFORM_REVENUE', 'USD';
    ELSIF has_type_col AND NOT has_currency_col THEN
      EXECUTE v_sql USING v_user_id, 'Cuenta Plataforma - Ingresos', 'PLATFORM_REVENUE';
    ELSIF NOT has_type_col AND has_currency_col THEN
      EXECUTE v_sql USING v_user_id, 'Cuenta Plataforma - Ingresos', 'USD';
    ELSE
      EXECUTE v_sql USING v_user_id, 'Cuenta Plataforma - Ingresos';
    END IF;
  END IF;

  RAISE NOTICE 'Platform revenue user ensured: % (id=%). Account ensured=%', v_email, v_user_id, NOT v_exists_account;
END
$$ LANGUAGE plpgsql;

-- =====================================================================
-- End of script
-- =====================================================================
