-- Purpose: Ensure constraints, indexes, and trigger state for delivery processing
-- Safe to run multiple times

DO $$
DECLARE
  v_has_unique boolean;
BEGIN
  -- Ensure unique constraint for idempotency exists
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND t.relname = 'account_transactions'
      AND c.conname = 'uq_account_txn_order_account_type'
  ) INTO v_has_unique;

  IF NOT v_has_unique THEN
    EXECUTE 'ALTER TABLE public.account_transactions
             ADD CONSTRAINT uq_account_txn_order_account_type
             UNIQUE (order_id, account_id, type)';
    RAISE NOTICE '✅ Created unique constraint uq_account_txn_order_account_type';
  ELSE
    RAISE NOTICE 'ℹ️  Unique constraint uq_account_txn_order_account_type already present';
  END IF;
END $$;

-- Helpful indexes (no-ops if already exist)
CREATE INDEX IF NOT EXISTS idx_account_txn_order ON public.account_transactions(order_id);
CREATE INDEX IF NOT EXISTS idx_account_txn_account ON public.account_transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_account_txn_type ON public.account_transactions(type);
CREATE INDEX IF NOT EXISTS idx_account_txn_settlement ON public.account_transactions(settlement_id);
CREATE INDEX IF NOT EXISTS idx_settlements_status ON public.settlements(status);

-- Sanity: ensure only the v3 trigger is active for delivered transitions
DO $$
DECLARE
  v_others int;
BEGIN
  SELECT COUNT(*) INTO v_others
  FROM information_schema.triggers
  WHERE event_object_schema = 'public'
    AND event_object_table = 'orders'
    AND trigger_name <> 'trg_on_order_delivered_process_v3'
    AND (trigger_name ILIKE '%deliver%' OR trigger_name ILIKE '%payment%');

  RAISE NOTICE '🔎 Other delivery/payment triggers on orders: %', v_others;
END $$;
