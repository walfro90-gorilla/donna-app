-- =============================================================
-- Fix RLS recursion on public.users (idempotent)
--
-- Goal: Remove any recursive/complex SELECT policies on public.users
--       and install a single, flat, non-recursive SELECT policy.
--
-- Why: You were getting
--   PostgrestException: infinite recursion detected in policy for relation "users"
-- which happens when a users policy references orders (or other tables) that
-- in turn reference users again, forming a cycle.
--
-- Notes:
-- - We use DO blocks with EXECUTE for DDL inside plpgsql (required by Postgres).
-- - We drop only SELECT policies on public.users to avoid touching INSERT/UPDATE/DELETE.
-- - We then create a basic non-recursive policy TO role "authenticated".
-- - Script is safe to re-run (idempotent): it drops existing SELECT policies
--   and creates the desired one only if it's missing.
-- =============================================================

-- 1) Ensure RLS is enabled on users
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- 2) Drop ALL existing SELECT policies on public.users (avoid recursion)
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'users'
      AND cmd        = 'SELECT'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', pol.policyname, pol.schemaname, pol.tablename);
  END LOOP;
END $$;

-- 3) Create a simple non-recursive SELECT policy for authenticated users (only if missing)
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
    EXECUTE $$
      CREATE POLICY users_select_authenticated_basic
      ON public.users
      AS PERMISSIVE
      FOR SELECT
      TO authenticated
      USING (true)
    $$;
  END IF;
END $$;

-- Optional: If you need anonymous read access for public profiles, you can
-- create a second policy scoped to anon with a stricter USING clause, but keep
-- it non-recursive (no subqueries back into users/orders/etc.).
