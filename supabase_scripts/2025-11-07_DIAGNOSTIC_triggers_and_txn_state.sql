-- List active triggers on orders and summarize transaction duplicates (diagnostics)

-- 1) Triggers on orders
SELECT
  t.tgname AS trigger_name,
  p.proname AS function_name,
  t.tgenabled,
  t.tgtype
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE t.tgrelid = 'public.orders'::regclass
  AND NOT t.tgisinternal
ORDER BY t.tgname;

-- 2) Duplicate groups by (order_id, account_id, type)
WITH d AS (
  SELECT order_id, account_id, type, COUNT(*) c
  FROM public.account_transactions
  GROUP BY 1,2,3
  HAVING COUNT(*) > 1
)
SELECT COUNT(*) AS duplicate_groups, COALESCE(SUM(c - 1), 0) AS extra_rows
FROM d;

-- 3) Per-order breakdown (optional; replace the UUID below)
-- SELECT type, account_id, COUNT(*)
-- FROM public.account_transactions
-- WHERE order_id = '00000000-0000-0000-0000-000000000000'
-- GROUP BY 1,2
-- ORDER BY 1,2;
