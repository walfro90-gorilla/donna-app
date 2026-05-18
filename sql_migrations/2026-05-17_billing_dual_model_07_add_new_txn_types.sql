-- =============================================================================
-- BILLING DUAL MODEL - 07 FIX: ampliar check constraint de account_transactions
--
-- Bug detectado en stress test E2E (2026-05-18):
--   El trigger v5 inserta tipos 'TIP_EARNING' y 'SUBSCRIPTION_FEE' que no
--   estaban permitidos por el CHECK constraint preexistente.
--   Resultado: violación 23514 al entregar una orden con tip o al marcar
--   una invoice como pagada.
--
-- Fix: extender el array de tipos permitidos.
-- =============================================================================

BEGIN;

ALTER TABLE public.account_transactions
DROP CONSTRAINT account_transactions_type_check;

ALTER TABLE public.account_transactions
ADD CONSTRAINT account_transactions_type_check CHECK (
  type = ANY (ARRAY[
    'ORDER_REVENUE'::text,
    'PLATFORM_COMMISSION'::text,
    'DELIVERY_EARNING'::text,
    'CASH_COLLECTED'::text,
    'SETTLEMENT_PAYMENT'::text,
    'SETTLEMENT_RECEPTION'::text,
    'RESTAURANT_PAYABLE'::text,
    'DELIVERY_PAYABLE'::text,
    'PLATFORM_DELIVERY_MARGIN'::text,
    'PLATFORM_NOT_DELIVERED_REFUND'::text,
    'CLIENT_DEBT'::text,
    'SUBSCRIPTION_FEE'::text,
    'TIP_EARNING'::text
  ])
);

COMMIT;
