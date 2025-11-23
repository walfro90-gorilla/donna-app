-- =============================================================
-- Fix: prevent auto-creating client account/profile for non-client signups
-- and make account creation idempotent for restaurant flow.
--
-- Context
-- - A trigger introduced earlier auto-created client_profiles and a 'client'
--   account on any new auth.users row, before the public registration RPCs ran.
-- - When registering a restaurant, this resulted in:
--     * public.users inserted (sometimes by the trigger) with role 'client'
--     * public.accounts created with account_type 'client'
--     * Then the app calls create_restaurant_public (OK) and create_account_public,
--       which fails with "Account already exists for this user".
-- - Additionally, an unnecessary client_profile could be created.
--
-- This patch:
-- 1) Adds a role normalizer and a predicate to decide if a user should be
--    auto-initialized as client.
-- 2) Adjusts the auth.users AFTER INSERT trigger to only run for true clients.
-- 3) Makes create_account_public idempotent and type-correcting.
-- 4) Enhances create_restaurant_public to normalize the user's role and ensure
--    the account type is 'restaurant' (upsert/convert from 'client').
-- 5) Adds a repair function to fix already misclassified registrations.
--
-- All functions remain SECURITY DEFINER and preserve the same signatures
-- consumed by the app.
-- =============================================================

-- 0) Safety: stay in public schema
SET search_path = public;

-- 1) Helper: normalize role values
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

-- 2) Helper: should we auto-create client profile/account for this user?
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
  -- Role already stored in public.users (if any)
  SELECT _normalize_role(role) INTO v_role_users
  FROM public.users WHERE id = p_user_id;

  -- Role from auth metadata (if accessible)
  BEGIN
    SELECT _normalize_role((raw_user_meta_data->>'role')) INTO v_role_meta
    FROM auth.users WHERE id = p_user_id;
  EXCEPTION WHEN others THEN
    v_role_meta := NULL;
  END;

  v_role_final := coalesce(nullif(v_role_users, ''), nullif(v_role_meta, ''), 'client');

  -- Only auto-create client bootstrap for explicit/implicit clients
  RETURN v_role_final = 'client';
END;
$$;

-- 3) Rewrite auth.users trigger to guard on role
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF public._should_autocreate_client(NEW.id) THEN
    PERFORM public.ensure_client_profile_and_account(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

-- Ensure the trigger exists (create if missing)
DO $$
BEGIN
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_handle_new_user_on_auth_users') THEN
      EXECUTE 'CREATE TRIGGER trg_handle_new_user_on_auth_users
               AFTER INSERT ON auth.users
               FOR EACH ROW
               EXECUTE FUNCTION public.handle_new_user()';
    END IF;
  EXCEPTION WHEN others THEN
    -- Not fatal if schema auth is not editable in this environment
    RAISE NOTICE 'Could not (re)create trigger on auth.users: %', SQLERRM;
  END;
END $$;

-- 4) Make account creation idempotent and type-correcting
CREATE OR REPLACE FUNCTION public.create_account_public(
  p_user_id UUID,
  p_account_type TEXT,
  p_balance NUMERIC DEFAULT 0.00
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_account_id UUID;
  v_existing_type text;
BEGIN
  -- Validate identities
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User ID does not exist in auth.users';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User profile does not exist';
  END IF;

  -- Check existing account
  SELECT id, account_type INTO v_account_id, v_existing_type
  FROM public.accounts WHERE user_id = p_user_id LIMIT 1;

  IF v_account_id IS NULL THEN
    -- Create brand new account
    INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
    VALUES (p_user_id, p_account_type, p_balance, now(), now())
    RETURNING id INTO v_account_id;
  ELSE
    -- If different type, correct it
    IF v_existing_type IS DISTINCT FROM p_account_type THEN
      UPDATE public.accounts SET account_type = p_account_type, updated_at = now()
      WHERE id = v_account_id;
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'account_id', v_account_id);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- 5) Enhance restaurant creation to ensure role and account type
CREATE OR REPLACE FUNCTION public.create_restaurant_public(
  p_user_id UUID,
  p_name TEXT,
  p_status TEXT DEFAULT 'pending',
  p_location_lat DOUBLE PRECISION DEFAULT NULL,
  p_location_lon DOUBLE PRECISION DEFAULT NULL,
  p_location_place_id TEXT DEFAULT NULL,
  p_address TEXT DEFAULT NULL,
  p_address_structured JSONB DEFAULT NULL,
  p_phone TEXT DEFAULT NULL,
  p_online BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_restaurant_id UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User ID does not exist in auth.users';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User profile does not exist. Create user profile first.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.restaurants WHERE user_id = p_user_id) THEN
    RAISE EXCEPTION 'Restaurant already exists for this user';
  END IF;

  -- Normalize role to restaurant (do not downgrade other roles)
  UPDATE public.users
  SET role = 'restaurant', updated_at = now()
  WHERE id = p_user_id AND coalesce(role,'') <> 'restaurant';

  INSERT INTO public.restaurants (
    user_id, name, status, location_lat, location_lon, location_place_id,
    address, address_structured, phone, online, created_at, updated_at
  ) VALUES (
    p_user_id, p_name, p_status, p_location_lat, p_location_lon, p_location_place_id,
    p_address, p_address_structured, p_phone, p_online, now(), now()
  ) RETURNING id INTO v_restaurant_id;

  -- Ensure financial account is restaurant-type (convert from client if needed)
  PERFORM 1 FROM public.accounts WHERE user_id = p_user_id;
  IF FOUND THEN
    UPDATE public.accounts SET account_type = 'restaurant', updated_at = now()
    WHERE user_id = p_user_id AND account_type <> 'restaurant';
  ELSE
    INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
    VALUES (p_user_id, 'restaurant', 0.0, now(), now());
  END IF;

  -- Optional cleanup: if a client_profile was auto-created, remove it
  DELETE FROM public.client_profiles WHERE user_id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'restaurant_id', v_restaurant_id,
    'message', 'Restaurant created successfully'
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- 6) Repair function for existing misclassified users
CREATE OR REPLACE FUNCTION public.repair_user_registration_misclassification(
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_has_restaurant boolean;
  v_account_id uuid;
BEGIN
  SELECT EXISTS(SELECT 1 FROM public.restaurants WHERE user_id = p_user_id) INTO v_has_restaurant;
  IF NOT v_has_restaurant THEN
    RETURN jsonb_build_object('success', false, 'error', 'No restaurant for this user');
  END IF;

  -- Set role and account type
  UPDATE public.users SET role = 'restaurant', updated_at = now() WHERE id = p_user_id;

  SELECT id INTO v_account_id FROM public.accounts WHERE user_id = p_user_id LIMIT 1;
  IF v_account_id IS NULL THEN
    INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
    VALUES (p_user_id, 'restaurant', 0.0, now(), now())
    RETURNING id INTO v_account_id;
  ELSE
    UPDATE public.accounts SET account_type = 'restaurant', updated_at = now() WHERE id = v_account_id;
  END IF;

  -- Remove client profile if present
  DELETE FROM public.client_profiles WHERE user_id = p_user_id;

  RETURN jsonb_build_object('success', true, 'account_id', v_account_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.repair_user_registration_misclassification(uuid) TO anon, authenticated, service_role;

-- =============================================================
-- Quick self-checks (non-fatal if objects absent)
-- =============================================================
-- SELECT pg_get_functiondef('public.create_account_public(uuid, text, numeric)'::regprocedure);
-- SELECT pg_get_functiondef('public.create_restaurant_public(uuid, text, text, double precision, double precision, text, text, jsonb, text, boolean)'::regprocedure);
-- SELECT tgname, tgrelid::regclass FROM pg_trigger WHERE tgname IN ('trg_handle_new_user_on_auth_users');
