-- Purpose: Reaffirm presence of unique constraint and helpful indexes. No-op if they already exist.
-- Safe to run multiple times.

BEGIN;

-- 1) Ensure the unique constraint exists on (order_id, account_id, type)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE c.conname = 'uq_account_txn_order_account_type'
      AND n.nspname = 'public'
      AND t.relname = 'account_transactions'
  ) THEN
    EXECUTE 'ALTER TABLE public.account_transactions
             ADD CONSTRAINT uq_account_txn_order_account_type
             UNIQUE (order_id, account_id, type)';
  END IF;
END $$;

-- 2) Helpful covering index for fast lookup by order
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'idx_account_txn_order'
      AND n.nspname = 'public'
  ) THEN
    EXECUTE 'CREATE INDEX idx_account_txn_order
             ON public.account_transactions (order_id, type, created_at DESC)';
  END IF;
END $$;

COMMIT;
