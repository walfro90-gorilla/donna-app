-- Purpose: Ensure a single, correct trigger processes delivered orders using existing function v3
-- Key fix: Use proper Postgres syntax for dropping triggers (DROP TRIGGER ... ON table)
-- Safe to run multiple times.

BEGIN;

-- 1) Drop legacy/duplicate triggers that may also write financial transactions
DROP TRIGGER IF EXISTS trg_auto_process_payment_on_delivery ON public.orders;
DROP TRIGGER IF EXISTS trg_on_order_delivered_balance0 ON public.orders;

-- Also drop any prior variants we might have created during troubleshooting
DROP TRIGGER IF EXISTS trigger_process_order_delivery_v3 ON public.orders;
DROP TRIGGER IF EXISTS trg_on_order_delivered_process_v3 ON public.orders;
DROP TRIGGER IF EXISTS trg_on_order_delivered_process_single ON public.orders;

-- 2) Create a single AFTER UPDATE trigger that only fires when status changes to DELIVERED
CREATE TRIGGER trg_on_order_delivered_process_v3
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'DELIVERED')
EXECUTE FUNCTION public.process_order_delivery_v3();

COMMIT;
