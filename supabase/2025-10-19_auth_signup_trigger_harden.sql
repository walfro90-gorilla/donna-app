-- =============================================================
-- Harden auth.users signup trigger to NEVER block user creation
-- Context: 500 "Database error saving new user" during signup
-- Root cause: trigger function raised unhandled exception while
--             auto-initializing client artifacts.
-- Fix: wrap logic with EXCEPTION handler and keep side-effects
--      best-effort. Also keep role-based guard to run only for
--      true clients.
-- =============================================================

SET search_path = public;

-- Safety helpers (no-ops if already defined by previous patches)
CREATE OR REPLACE FUNCTION public._normalize_role(p_raw text)
RETURNS text
LANGUAGE sql
AS $$
  SELECT CASE lower(coalesce(p_raw, ''))
    WHEN 'client' THEN 'client'
    WHEN 'cliente' THEN 'client'
    WHEN 'user' THEN 'client'
    WHEN 'usuario' THEN 'client'
    WHEN 'restaurant' THEN 'restaurant'
    WHEN 'restaurante' THEN 'restaurant'
    WHEN 'delivery' THEN 'delivery_agent'
    WHEN 'repartidor' THEN 'delivery_agent'
    WHEN 'delivery_agent' THEN 'delivery_agent'
    WHEN 'rider' THEN 'delivery_agent'
    WHEN 'courier' THEN 'delivery_agent'
    WHEN 'admin' THEN 'admin'
    WHEN 'administrator' THEN 'admin'
    ELSE ''
  END;
$$;

CREATE OR REPLACE FUNCTION public._should_autocreate_client(p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_role_users text;
  v_role_meta  text;
  v_role_final text;
BEGIN
  -- existing role in public.users (if any)
  SELECT _normalize_role(role) INTO v_role_users
  FROM public.users WHERE id = p_user_id;

  -- role from auth metadata (if accessible)
  BEGIN
    SELECT _normalize_role((raw_user_meta_data->>'role')) INTO v_role_meta
    FROM auth.users WHERE id = p_user_id;
  EXCEPTION WHEN others THEN
    v_role_meta := NULL; -- never fail
  END;

  v_role_final := coalesce(nullif(v_role_users,''), nullif(v_role_meta,''), 'client');
  RETURN v_role_final = 'client';
END;
$$;

-- Hardened trigger function: never raises, logs instead
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  BEGIN
    IF public._should_autocreate_client(NEW.id) THEN
      PERFORM public.ensure_client_profile_and_account(NEW.id);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Do not block auth signup; just log the error
    RAISE NOTICE 'handle_new_user failed for %: %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END;
$$;

-- Recreate trigger to ensure it points to the hardened function
DO $$
BEGIN
  BEGIN
    -- If trigger exists, drop and recreate to ensure latest function is used
    IF EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgname = 'trg_handle_new_user_on_auth_users'
    ) THEN
      EXECUTE 'DROP TRIGGER trg_handle_new_user_on_auth_users ON auth.users';
    END IF;

    EXECUTE 'CREATE TRIGGER trg_handle_new_user_on_auth_users
             AFTER INSERT ON auth.users
             FOR EACH ROW
             EXECUTE FUNCTION public.handle_new_user()';
  EXCEPTION WHEN OTHERS THEN
    -- Some environments restrict creating triggers on auth.users; do not fail
    RAISE NOTICE 'Cannot (re)create trigger on auth.users: %', SQLERRM;
  END;
END $$;

-- Optional sanity checks (non-fatal if missing perms)
-- SELECT tgname FROM pg_trigger WHERE tgname = 'trg_handle_new_user_on_auth_users';
-- SELECT pg_get_functiondef('public.handle_new_user()'::regprocedure);

-- =============================================================
-- End of script
-- =============================================================
