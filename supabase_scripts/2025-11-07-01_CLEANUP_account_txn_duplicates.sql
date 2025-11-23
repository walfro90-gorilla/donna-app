-- Purpose: Remove duplicate rows in public.account_transactions keeping the most recent per (order_id, account_id, type)
-- Safe to run multiple times.

BEGIN;

WITH ranked AS (
  SELECT 
    ctid,
    ROW_NUMBER() OVER (
      PARTITION BY order_id, account_id, type 
      ORDER BY COALESCE(created_at, NOW()) DESC, id DESC
    ) AS rn
  FROM public.account_transactions
)
DELETE FROM public.account_transactions t
USING ranked r
WHERE t.ctid = r.ctid
  AND r.rn > 1;

-- Optional: verify no duplicates remain (will return 0 rows if clean)
-- SELECT order_id, account_id, type, COUNT(*)
-- FROM public.account_transactions
-- GROUP BY order_id, account_id, type
-- HAVING COUNT(*) > 1;

COMMIT;
