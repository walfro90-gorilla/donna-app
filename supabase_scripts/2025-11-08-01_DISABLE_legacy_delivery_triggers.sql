-- Purpose: Disable/remove ALL legacy triggers/functions that write financials on order delivery
-- Safe, idempotent. Drops only delivery-related writers. Does NOT touch unrelated triggers.

BEGIN;

-- Drop known legacy/duplicate delivery triggers on public.orders
DROP TRIGGER IF EXISTS trg_auto_process_payment_on_delivery ON public.orders;
DROP TRIGGER IF EXISTS trg_on_order_delivered_balance0 ON public.orders;
DROP TRIGGER IF EXISTS trigger_process_order_delivery_v3 ON public.orders;
DROP TRIGGER IF EXISTS trg_on_order_delivered_process_v3 ON public.orders;
DROP TRIGGER IF EXISTS trg_on_order_delivered_process_single ON public.orders;
DROP TRIGGER IF EXISTS trigger_process_order_payment_final ON public.orders;
DROP TRIGGER IF EXISTS trigger_process_order_payment_v2_canonical ON public.orders;
DROP TRIGGER IF EXISTS trg_process_payments_on_delivery ON public.orders;
DROP TRIGGER IF EXISTS trigger_process_payment_on_delivery ON public.orders;
DROP TRIGGER IF EXISTS trigger_order_financial_completion ON public.orders;
DROP TRIGGER IF EXISTS trigger_process_order_payment ON public.orders;
DROP TRIGGER IF EXISTS trg_order_status_update ON public.orders;

-- Drop legacy functions if they exist (keep safe list only for delivery-financials)
DROP FUNCTION IF EXISTS public.process_order_payment_final() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment_v2() CASCADE;
DROP FUNCTION IF EXISTS public.process_payments_on_delivery() CASCADE;
DROP FUNCTION IF EXISTS public.process_payment_on_delivery() CASCADE;
DROP FUNCTION IF EXISTS public.handle_order_financial_completion() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_delivery_v3() CASCADE;
DROP FUNCTION IF EXISTS public.fn_on_order_delivered_balance0() CASCADE;

COMMIT;
