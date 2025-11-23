-- Consolidate order delivery processing to a single trigger/function
-- Drops legacy triggers that cause duplicate inserts into account_transactions
-- Re-creates the canonical trigger pointing to process_order_delivery_v3()

BEGIN;

-- Safety: ensure the orders table exists
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'orders'
  ) THEN
    RAISE EXCEPTION 'Table public.orders does not exist';
  END IF;
END $$;

-- Drop legacy triggers if they exist
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.orders'::regclass AND tgname = 'trg_auto_process_payment_on_delivery'
  ) THEN
    EXECUTE 'ALTER TABLE public.orders DROP TRIGGER IF EXISTS trg_auto_process_payment_on_delivery';
    RAISE NOTICE 'Dropped trigger: trg_auto_process_payment_on_delivery';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.orders'::regclass AND tgname = 'trg_on_order_delivered_balance0'
  ) THEN
    EXECUTE 'ALTER TABLE public.orders DROP TRIGGER IF EXISTS trg_on_order_delivered_balance0';
    RAISE NOTICE 'Dropped trigger: trg_on_order_delivered_balance0';
  END IF;
END $$;

-- Recreate the canonical trigger to avoid duplicates or misconfigured timing
-- This ensures the trigger is AFTER UPDATE OF status and only fires on delivered transition
ALTER TABLE public.orders DROP TRIGGER IF EXISTS trigger_process_order_delivery_v3;

CREATE TRIGGER trigger_process_order_delivery_v3
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
WHEN (NEW.status = 'delivered' AND (OLD.status IS DISTINCT FROM NEW.status))
EXECUTE FUNCTION public.process_order_delivery_v3();

-- Ensure enabled
ALTER TABLE public.orders ENABLE TRIGGER trigger_process_order_delivery_v3;

COMMIT;

-- Diagnostics (optional to run manually after):
-- SELECT t.tgname AS trigger_name, p.proname AS function_name, t.tgenabled, t.tgtype
-- FROM pg_trigger t
-- JOIN pg_proc p ON p.oid = t.tgfoid
-- WHERE t.tgrelid = 'public.orders'::regclass AND NOT t.tgisinternal
-- ORDER BY t.tgname;
