-- =============================================================
-- Fix RLS recursion on public.users and create a minimal SELECT policy
-- Version: v3 (uses distinct dollar-quote tag in EXECUTE to avoid syntax error)
-- Purpose: Resolve "infinite recursion detected in policy for relation 'users'"
-- Notes:
--  - Drops existing SELECT policies on public.users
--  - Creates a single, non-recursive SELECT policy for role "authenticated"
--  - Uses EXECUTE with $policy$ to avoid nested $$ collision inside DO $$ ... $$
--  - Idempotent: safe to re-run
-- =============================================================

-- Ensure RLS is ON (Supabase enables it by default, but we assert it)
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Drop all SELECT policies on public.users to break any recursive chains
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'users'
      AND cmd        = 'SELECT'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.users;', r.policyname);
  END LOOP;
END $$;

-- Create a minimal, non-recursive SELECT policy for authenticated role
-- Important: use a different dollar-quote tag ($policy$) to avoid colliding with DO $$ ... $$
DO $$
DECLARE
  exists_policy boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'users'
      AND policyname = 'users_select_authenticated_basic'
  ) INTO exists_policy;

  IF NOT exists_policy THEN
    EXECUTE $policy$
      CREATE POLICY users_select_authenticated_basic
      ON public.users
      AS PERMISSIVE
      FOR SELECT
      TO authenticated
      USING (true);
    $policy$;
  END IF;
END $$;

-- Optional: You may also want to allow service_role (bypasses RLS by default) or anon (usually not needed).
-- This script intentionally keeps the policy minimal to avoid reintroducing recursion.

-- Security note:
-- If you need to restrict which users are visible to authenticated clients,
-- prefer creating a dedicated view (e.g., public.user_public_view) with only non-sensitive columns
-- and expose a policy on that view, leaving base-table policies simple and non-recursive.
