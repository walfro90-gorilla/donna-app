-- =============================================================
-- Ensure user_preferences is created for new client accounts
-- Scope: Surgical change, extends existing ensure_client_profile_and_account
-- Safe, idempotent and aligned with current onboarding flags usage
-- =============================================================

-- Recreate function to append user_preferences creation without altering existing behavior
CREATE OR REPLACE FUNCTION public.ensure_client_profile_and_account(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_user_exists boolean;
  v_current_role text;
  v_account_id uuid;
BEGIN
  -- Validate auth user exists
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User % not found in auth.users', p_user_id;
  END IF;

  -- Ensure minimal public.users row (default role client)
  SELECT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id), role
    INTO v_user_exists, v_current_role
  FROM public.users WHERE id = p_user_id;

  IF NOT v_user_exists THEN
    INSERT INTO public.users (id, role, created_at, updated_at)
    VALUES (p_user_id, 'client', v_now, v_now)
    ON CONFLICT (id) DO NOTHING;
  ELSE
    -- Normalize role only if empty/client variants; never overwrite restaurant/delivery/admin
    IF COALESCE(v_current_role, '') IN ('', 'client', 'cliente') THEN
      UPDATE public.users SET role = 'client', updated_at = v_now WHERE id = p_user_id;
    END IF;
  END IF;

  -- Ensure client profile
  INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
  VALUES (p_user_id, 'active', v_now, v_now)
  ON CONFLICT (user_id) DO UPDATE
    SET updated_at = EXCLUDED.updated_at;

  -- Ensure financial account (type 'client') with zero balance
  SELECT id INTO v_account_id
  FROM public.accounts
  WHERE user_id = p_user_id AND account_type = 'client'
  LIMIT 1;
  IF v_account_id IS NULL THEN
    INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
    VALUES (p_user_id, 'client', 0.0, v_now, v_now)
    RETURNING id INTO v_account_id;
  END IF;

  -- NEW: Ensure user_preferences row exists (defaults)
  -- Keep it minimal to avoid schema drift across environments
  BEGIN
    INSERT INTO public.user_preferences (user_id)
    VALUES (p_user_id)
    ON CONFLICT (user_id) DO NOTHING;
  EXCEPTION WHEN undefined_table THEN
    -- If user_preferences table is not present in this environment, do not fail the whole function
    RAISE NOTICE 'user_preferences table not found; skipping preferences creation';
  WHEN others THEN
    -- Never block account/profile creation due to preferences; just log
    RAISE NOTICE 'user_preferences upsert skipped due to: %', SQLERRM;
  END;

  RETURN jsonb_build_object('success', true, 'account_id', v_account_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_client_profile_and_account(uuid) TO anon, authenticated, service_role;

-- Notes:
-- - This script only redefines the function; all triggers and callers remain intact.
-- - It is safe to run multiple times.
