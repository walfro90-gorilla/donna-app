-- Purpose: Recompute account balances from ledger and verify zero-sum by order

BEGIN;

-- Recompute balances from authoritative ledger
UPDATE public.accounts AS a
SET balance = COALESCE(t.sum_amount, 0),
    updated_at = NOW()
FROM (
  SELECT account_id, SUM(amount) AS sum_amount
  FROM public.account_transactions
  GROUP BY account_id
) AS t
WHERE a.id = t.account_id;

-- Ensure accounts with no transactions are zeroed
UPDATE public.accounts AS a
SET balance = 0,
    updated_at = NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM public.account_transactions at WHERE at.account_id = a.id
);

COMMIT;

-- Optional verifications (read-only):
-- 1) Check per-order net must be (near) zero
-- SELECT order_id, ROUND(SUM(amount)::numeric, 2) AS net
-- FROM public.account_transactions
-- GROUP BY order_id
-- HAVING ABS(SUM(amount)) > 0.01
-- ORDER BY ABS(SUM(amount)) DESC
-- LIMIT 30;

-- 2) Recent balances snapshot
-- SELECT a.id, a.account_type, a.balance, u.email
-- FROM public.accounts a
-- LEFT JOIN public.users u ON u.id = a.user_id
-- ORDER BY a.updated_at DESC
-- LIMIT 50;
