-- fix_ambiguous_register_client.sql
-- Purpose: Remove ALL overloaded versions of public.register_client to avoid
--          ambiguity before recreating the canonical RPC.
-- Safe to run multiple times. No-op if none found.

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT n.nspname  AS schema_name,
           p.proname  AS func_name,
           oidvectortypes(p.proargtypes) AS argtypes
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'register_client'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s);', r.schema_name, r.func_name, r.argtypes);
  END LOOP;
END $$;
