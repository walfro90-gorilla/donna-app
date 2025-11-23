-- Remove duplicate account_transactions keeping the most recent per (order_id, account_id, type)

BEGIN;

-- Safety: ensure the table exists
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'account_transactions'
  ) THEN
    RAISE EXCEPTION 'Table public.account_transactions does not exist';
  END IF;
END $$;

-- Delete duplicates while keeping the newest row per unique key
WITH ranked AS (
  SELECT id
  FROM (
    SELECT id,
           row_number() OVER (
             PARTITION BY order_id, account_id, type
             ORDER BY created_at DESC NULLS LAST, id DESC
           ) AS rn
    FROM public.account_transactions
  ) s
  WHERE rn > 1
)
DELETE FROM public.account_transactions a
USING ranked r
WHERE a.id = r.id;

COMMIT;

-- Verification query (run manually):
-- WITH d AS (
--   SELECT order_id, account_id, type, COUNT(*) c
--   FROM public.account_transactions
--   GROUP BY 1,2,3
--   HAVING COUNT(*) > 1
-- )
-- SELECT COUNT(*) AS remaining_duplicate_groups FROM d;
