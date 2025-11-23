-- Purpose: Recompute accounts.balance from the authoritative ledger
-- Idempotent and safe to run after any ledger cleanup/migrations

BEGIN;

-- Update balances for accounts that have at least one transaction
UPDATE public.accounts AS a
SET balance = COALESCE(t.sum_amount, 0),
    updated_at = NOW()
FROM (
  SELECT account_id, SUM(amount) AS sum_amount
  FROM public.account_transactions
  GROUP BY account_id
) AS t
WHERE a.id = t.account_id;

-- Ensure accounts with no transactions are set to zero (optional safety)
UPDATE public.accounts AS a
SET balance = 0,
    updated_at = NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM public.account_transactions at WHERE at.account_id = a.id
);

COMMIT;

-- Verification suggestion (read-only):
-- SELECT id, account_type, balance FROM public.accounts ORDER BY updated_at DESC LIMIT 50;
