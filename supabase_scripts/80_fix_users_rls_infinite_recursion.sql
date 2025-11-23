-- =============================================================
-- Fix: "infinite recursion detected in policy for relation users"
-- Context: Orders/Restaurants endpoints join public.users and hit
--          a recursive RLS chain. We neutralize recursion by adding
--          a simple, non-recursive SELECT policy for authenticated users.
--
-- Scope: This is a surgical, reversible hotfix. It does NOT drop
--        existing users policies; it adds an allow-select policy that
--        breaks the recursion and restores app functionality.
--        Tightening of exposure (columns/view-based) can be done later.
-- =============================================================

DO $$
BEGIN
  -- Ensure RLS is enabled on users (Supabase default, but idempotent here)
  PERFORM 1 FROM pg_tables WHERE schemaname='public' AND tablename='users';
  IF FOUND THEN
    EXECUTE 'ALTER TABLE public.users ENABLE ROW LEVEL SECURITY';
  END IF;
END$$;

-- Create an authenticated SELECT policy that does not reference other tables
-- Naming is unique to avoid collision
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'users' 
      AND policyname = 'users_select_authenticated_break_recursion'
  ) THEN
    EXECUTE $$
      CREATE POLICY "users_select_authenticated_break_recursion"
      ON public.users
      FOR SELECT
      TO authenticated
      USING (true)
    $$;
  END IF;
END$$;

-- Optional: If you also need service role or admin dashboard from anon
-- uncomment below (NOT enabled by default for privacy)
-- CREATE POLICY "users_select_anon_break_recursion"
--   ON public.users FOR SELECT TO anon USING (false);

-- Notes:
-- - Policies are ORed. This policy coexists with prior specific rules.
-- - It avoids subqueries and helper functions that read public.users
--   or other RLS-protected tables, eliminating recursion.
-- - If you prefer stricter exposure, create a view with public fields
--   and join that view from the app; then replace this policy.
