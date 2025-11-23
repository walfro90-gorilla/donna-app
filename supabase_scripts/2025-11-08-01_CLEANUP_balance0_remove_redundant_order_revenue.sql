-- Purpose: Fix per-order zero-balance by removing redundant ORDER_REVENUE lines
-- Context: When an order is delivered, we already record the cash/payment intake
--          (CASH_COLLECTED or PAYMENT_CAPTURED) and the full distribution lines
--          (RESTAURANT_PAYABLE, DELIVERY_EARNING, PLATFORM_COMMISSION,
--           PLATFORM_DELIVERY_MARGIN). Keeping ORDER_REVENUE as an extra line
--          causes the sum(amount) per order to be > 0.
--
-- This cleanup removes ORDER_REVENUE only when it is redundant:
--  - The order has CASH_COLLECTED or PAYMENT_CAPTURED, and
--  - The order has at least one distribution line.
--
-- Idempotent: safe to run multiple times. It won’t touch orders that only have
--             ORDER_REVENUE without the other lines.

BEGIN;

WITH orders_with_redundant_revenue AS (
  SELECT at.order_id
  FROM public.account_transactions AS at
  WHERE at.order_id IS NOT NULL
  GROUP BY at.order_id
  HAVING bool_or(at.type = 'ORDER_REVENUE')
     AND (
       bool_or(at.type = 'CASH_COLLECTED')
       OR bool_or(at.type = 'PAYMENT_CAPTURED')
     )
     AND (
       bool_or(at.type = 'PLATFORM_COMMISSION')
       OR bool_or(at.type = 'RESTAURANT_PAYABLE')
       OR bool_or(at.type = 'DELIVERY_EARNING')
       OR bool_or(at.type = 'PLATFORM_DELIVERY_MARGIN')
     )
)
DELETE FROM public.account_transactions r
USING orders_with_redundant_revenue o
WHERE r.order_id = o.order_id
  AND r.type = 'ORDER_REVENUE';

COMMIT;

-- Verification suggestion (read-only):
-- SELECT order_id, ROUND(SUM(amount)::numeric, 2) AS net
-- FROM public.account_transactions
-- GROUP BY order_id
-- HAVING ABS(SUM(amount)) > 0.01
-- ORDER BY ABS(SUM(amount)) DESC
-- LIMIT 20;
