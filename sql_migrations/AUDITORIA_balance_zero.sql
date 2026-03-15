-- ============================================================================
-- AUDITORÍA BALANCE 0 — Ejecutar en Supabase Dashboard → SQL Editor
-- Responde: ¿Las transacciones son correctas y el balance es realmente 0?
-- ============================================================================

-- 1) SALUD GLOBAL: suma de todos los balances de cuentas (debe ser $0.00)
SELECT
  ROUND(SUM(balance)::numeric, 2)      AS sistema_net,
  CASE WHEN ABS(SUM(balance)) < 0.01
       THEN '✅ SISTEMA BALANCEADO'
       ELSE '❌ DESBALANCE DETECTADO'
  END AS estado
FROM public.accounts;

-- 2) BALANCE POR TIPO DE CUENTA
SELECT
  account_type,
  COUNT(*)                             AS cuentas,
  ROUND(SUM(balance)::numeric, 2)      AS total_balance
FROM public.accounts
GROUP BY account_type
ORDER BY account_type;

-- 3) ÓRDENES CON TRANSACCIONES QUE NO SUMAN $0 (excluye CLIENT_DEBT)
--    Si aparecen aquí → esas órdenes tienen transacciones incompletas en DB
SELECT
  order_id,
  ROUND(SUM(amount)::numeric, 2)       AS delta,
  COUNT(*)                             AS num_txs,
  STRING_AGG(DISTINCT type, ', ')      AS tipos
FROM public.account_transactions
WHERE order_id IS NOT NULL
  AND type != 'CLIENT_DEBT'
GROUP BY order_id
HAVING ABS(SUM(amount)) > 0.01
ORDER BY ABS(SUM(amount)) DESC
LIMIT 50;

-- 4) RESUMEN: cuántas órdenes están balanceadas vs desbalanceadas
SELECT
  COUNT(*)                             AS total_ordenes_con_txs,
  SUM(CASE WHEN ABS(delta) < 0.01 THEN 1 ELSE 0 END) AS balanceadas,
  SUM(CASE WHEN ABS(delta) >= 0.01 THEN 1 ELSE 0 END) AS desbalanceadas
FROM (
  SELECT order_id, SUM(amount) AS delta
  FROM public.account_transactions
  WHERE order_id IS NOT NULL
    AND type != 'CLIENT_DEBT'
  GROUP BY order_id
) sub;

-- 5) TRANSACCIONES DE SETTLEMENTS (order_id IS NULL) — deben sumar $0 en pares
SELECT
  type,
  COUNT(*)                             AS num,
  ROUND(SUM(amount)::numeric, 2)       AS total
FROM public.account_transactions
WHERE order_id IS NULL
GROUP BY type
ORDER BY type;

-- 6) DETALLE DE TIPOS DE TRANSACCIÓN (all time)
SELECT
  type,
  COUNT(*)                             AS num_txs,
  ROUND(SUM(amount)::numeric, 2)       AS total_amount
FROM public.account_transactions
WHERE type != 'CLIENT_DEBT'
GROUP BY type
ORDER BY ABS(SUM(amount)) DESC;

-- ============================================================================
-- INTERPRETACIÓN:
-- Query 1: debe mostrar $0.00 → sistema sano
-- Query 3: órdenes vacías → no hay transacciones faltantes en DB
-- Query 4: desbalanceadas = 0 → todas las órdenes tienen sets completos
-- Query 5: SETTLEMENT_PAYMENT + SETTLEMENT_RECEPTION deberían cancelarse
-- ============================================================================
