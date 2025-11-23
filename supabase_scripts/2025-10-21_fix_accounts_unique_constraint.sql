-- =============================================================
-- Align accounts unique constraints with RPC ON CONFLICT usage
-- - Previous schema had UNIQUE(user_id) on public.accounts
-- - Our RPCs use ON CONFLICT (user_id, account_type)
-- This migration:
--   1) Drops any UNIQUE constraint solely on (user_id)
--   2) Creates UNIQUE(user_id, account_type) if missing
-- Idempotent and safe across environments
-- =============================================================

DO $$
DECLARE
  v_user_id_unique_name text;
  v_composite_unique_exists boolean := false;
BEGIN
  -- 1) Find and drop a unique constraint limited to column list {user_id}
  SELECT c.conname
    INTO v_user_id_unique_name
  FROM pg_constraint c
  JOIN pg_class t ON c.conrelid = t.oid
  JOIN pg_namespace n ON t.relnamespace = n.oid
  WHERE n.nspname = 'public'
    AND t.relname = 'accounts'
    AND c.contype = 'u'
    AND (
      SELECT array_agg(attname_txt ORDER BY attnum)
      FROM (
        SELECT a.attname::text AS attname_txt, a.attnum
        FROM unnest(c.conkey) AS k(attnum)
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
      ) s
    ) = ARRAY['user_id']::text[];

  IF v_user_id_unique_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.accounts DROP CONSTRAINT %I', v_user_id_unique_name);
  END IF;

  -- 2) Check if a composite unique on (user_id, account_type) already exists
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND t.relname = 'accounts'
      AND c.contype = 'u'
      AND (
        SELECT array_agg(attname_txt ORDER BY attnum)
        FROM (
          SELECT a.attname::text AS attname_txt, a.attnum
          FROM unnest(c.conkey) AS k(attnum)
          JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
        ) s
      ) = ARRAY['user_id','account_type']::text[]
  ) INTO v_composite_unique_exists;

  IF NOT v_composite_unique_exists THEN
    ALTER TABLE public.accounts
      ADD CONSTRAINT accounts_user_id_account_type_key UNIQUE (user_id, account_type);
  END IF;
END $$;

-- Optional: normalize existing rows to avoid dup types; no-op in most installs
-- You can review duplicates with (not executed automatically):
--   SELECT user_id, account_type, COUNT(*) FROM public.accounts GROUP BY 1,2 HAVING COUNT(*)>1;
