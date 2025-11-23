-- Purpose: Backfill to enforce per-order zero-sum without ORDER_REVENUE
-- Actions:
--  1) For delivered card orders missing the balancing CASH_COLLECTED line,
--     insert it on platform_payables with amount = -total_amount
--  2) Remove ORDER_REVENUE lines when distribution lines exist
-- Idempotent and aligned with supabase_scripts/DATABASE_SCHEMA.sql

BEGIN;

-- Resolve platform_payables account id (by type)
WITH pp AS (
  SELECT id AS platform_payables_id
  FROM public.accounts
  WHERE account_type = 'platform_payables'
  ORDER BY created_at DESC
  LIMIT 1
)
-- 1) Insert missing CASH_COLLECTED for card orders
INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
SELECT
  pp.platform_payables_id,
  'CASH_COLLECTED'::text,
  -o.total_amount,
  o.id,
  'Cobro por tarjeta (backfill) orden #' || LEFT(o.id::text, 8),
  jsonb_build_object('total', o.total_amount, 'payment_method', 'card', 'backfill', true)
FROM public.orders o
CROSS JOIN pp
WHERE o.status = 'delivered'
  AND o.payment_method = 'card'
  AND NOT EXISTS (
    SELECT 1 FROM public.account_transactions at
    WHERE at.order_id = o.id AND at.type = 'CASH_COLLECTED'
  )
ON CONFLICT DO NOTHING;

-- 2) Remove redundant ORDER_REVENUE when a balancing line and distributions exist
WITH orders_with_redundant AS (
  SELECT at.order_id
  FROM public.account_transactions at
  GROUP BY at.order_id
  HAVING bool_or(at.type = 'ORDER_REVENUE')
     AND bool_or(at.type = 'CASH_COLLECTED')
     AND (
       bool_or(at.type = 'PLATFORM_COMMISSION')
       OR bool_or(at.type = 'RESTAURANT_PAYABLE')
       OR bool_or(at.type = 'DELIVERY_EARNING')
       OR bool_or(at.type = 'PLATFORM_DELIVERY_MARGIN')
     )
)
DELETE FROM public.account_transactions r
USING orders_with_redundant owr
WHERE r.order_id = owr.order_id
  AND r.type = 'ORDER_REVENUE';

COMMIT;
