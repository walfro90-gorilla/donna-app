-- ============================================================================
-- AUDITORÍA BALANCE 0 — Ejecutar en Supabase Dashboard → SQL Editor
-- Responde: ¿Las transacciones son correctas y el balance es realmente 0?
--
-- ARQUITECTURA: contabilidad de doble entrada. Cada peso en el sistema
-- aparece en exactamente dos cuentas con signo opuesto. La suma global SIEMPRE
-- debe ser $0.00. Las órdenes de efectivo usan CLIENT_DEBT como entrada
-- de balance (excluirla da un delta = total_order, que es ESPERADO).
-- ============================================================================

-- ── 1) SALUD GLOBAL ─────────────────────────────────────────────────────────
--    Suma de todos los balances de todas las cuentas → debe ser $0.00
SELECT
  ROUND(SUM(balance)::numeric, 2)      AS sistema_net,
  CASE WHEN ABS(SUM(balance)) < 0.01
       THEN '✅ SISTEMA BALANCEADO'
       ELSE '❌ DESBALANCE DETECTADO'
  END AS estado
FROM public.accounts;

-- ── 2) BALANCE POR TIPO DE CUENTA ───────────────────────────────────────────
--    Lectura esperada:
--      client            → $0.00   (deudas liquidadas)
--      delivery_agent    → $0.00   (efectivo liquidado)
--      platform_payables → negativo (debe a restaurantes/repartidores)
--      platform_revenue  → positivo (comisiones ganadas)
--      restaurant        → neg/pos  (pendiente de cobrar o ya cobrado)
SELECT
  account_type,
  COUNT(*)                             AS cuentas,
  ROUND(SUM(balance)::numeric, 2)      AS total_balance
FROM public.accounts
GROUP BY account_type
ORDER BY account_type;

-- ── 3) ÓRDENES CON TIPOS DE TRANSACCIÓN FALTANTES ───────────────────────────
--    Detecta órdenes que NO tienen los 5 tipos esenciales.
--    NOTA: NO usamos SUM = $0 como criterio porque las órdenes de efectivo
--    balancean vía CLIENT_DEBT (cuenta del cliente), no en las 5 tx de orden.
--    Si esta query devuelve filas → esas órdenes tienen entradas incompletas.
SELECT
  at2.order_id,
  COUNT(DISTINCT at2.type)             AS tipos_presentes,
  STRING_AGG(DISTINCT at2.type, ', ' ORDER BY at2.type) AS tipos,
  CASE
    WHEN NOT BOOL_OR(at2.type = 'ORDER_REVENUE')          THEN '❌ falta ORDER_REVENUE'
    WHEN NOT BOOL_OR(at2.type = 'RESTAURANT_PAYABLE')     THEN '❌ falta RESTAURANT_PAYABLE'
    WHEN NOT BOOL_OR(at2.type = 'DELIVERY_EARNING')       THEN '❌ falta DELIVERY_EARNING'
    WHEN NOT BOOL_OR(at2.type = 'PLATFORM_COMMISSION')    THEN '❌ falta PLATFORM_COMMISSION'
    WHEN NOT BOOL_OR(at2.type = 'PLATFORM_DELIVERY_MARGIN') THEN '❌ falta PLATFORM_DELIVERY_MARGIN'
    ELSE '⚠️ conjunto incompleto'
  END AS problema
FROM public.account_transactions at2
WHERE at2.order_id IS NOT NULL
GROUP BY at2.order_id
HAVING NOT (
  BOOL_OR(type = 'ORDER_REVENUE') AND
  BOOL_OR(type = 'RESTAURANT_PAYABLE') AND
  BOOL_OR(type = 'DELIVERY_EARNING') AND
  BOOL_OR(type = 'PLATFORM_COMMISSION') AND
  BOOL_OR(type = 'PLATFORM_DELIVERY_MARGIN')
)
ORDER BY tipos_presentes ASC
LIMIT 50;

-- ── 4) RESUMEN: órdenes completas vs incompletas ─────────────────────────────
--    Completa = tiene los 5 tipos de tx esenciales. Incompleta = le falta alguno.
SELECT
  COUNT(*)                             AS total_ordenes,
  SUM(CASE WHEN tiene_5_tipos THEN 1 ELSE 0 END) AS completas,
  SUM(CASE WHEN NOT tiene_5_tipos THEN 1 ELSE 0 END) AS incompletas
FROM (
  SELECT
    order_id,
    BOOL_OR(type = 'ORDER_REVENUE') AND
    BOOL_OR(type = 'RESTAURANT_PAYABLE') AND
    BOOL_OR(type = 'DELIVERY_EARNING') AND
    BOOL_OR(type = 'PLATFORM_COMMISSION') AND
    BOOL_OR(type = 'PLATFORM_DELIVERY_MARGIN')  AS tiene_5_tipos
  FROM public.account_transactions
  WHERE order_id IS NOT NULL
  GROUP BY order_id
) sub;

-- ── 4b) DELTA POR ORDEN (incluye CLIENT_DEBT) — debe ser $0 por orden ────────
--    Con CLIENT_DEBT incluido cada orden debería sumar exactamente $0.
--    Si hay deltas ≠ $0 incluyendo CLIENT_DEBT → bug real de contabilidad.
SELECT
  order_id,
  ROUND(SUM(amount)::numeric, 2)       AS delta_con_client_debt,
  COUNT(*)                             AS num_txs,
  STRING_AGG(DISTINCT type, ', ' ORDER BY type) AS tipos
FROM public.account_transactions
WHERE order_id IS NOT NULL
GROUP BY order_id
HAVING ABS(SUM(amount)) > 0.01
ORDER BY ABS(SUM(amount)) DESC
LIMIT 50;

-- ── 5) TRANSACCIONES DE SETTLEMENTS (order_id IS NULL) — par PAYMENT/RECEPTION
--    SETTLEMENT_PAYMENT y SETTLEMENT_RECEPTION deben cancelarse entre sí ($0 neto).
SELECT
  type,
  COUNT(*)                             AS num,
  ROUND(SUM(amount)::numeric, 2)       AS total
FROM public.account_transactions
WHERE order_id IS NULL
GROUP BY type
ORDER BY type;

-- ── 6) DETALLE DE TIPOS DE TRANSACCIÓN (all time) ───────────────────────────
SELECT
  type,
  COUNT(*)                             AS num_txs,
  ROUND(SUM(amount)::numeric, 2)       AS total_amount
FROM public.account_transactions
GROUP BY type
ORDER BY ABS(SUM(amount)) DESC;

-- ── 7) DEUDAS DE CLIENTES PENDIENTES ────────────────────────────────────────
--    Muestra cuánto deben los clientes (órdenes no entregadas sin cobrar).
SELECT
  status,
  COUNT(*)                             AS num_deudas,
  ROUND(SUM(amount)::numeric, 2)       AS total_adeudado
FROM public.client_debts
GROUP BY status
ORDER BY status;

-- ============================================================================
-- INTERPRETACIÓN CORRECTA:
--
-- Query 1: $0.00 → sistema globalmente sano ✅
-- Query 2: platform_payables negativo + platform_revenue positivo = normal
-- Query 3: vacío → todas las órdenes tienen sus 5 transacciones esenciales ✅
-- Query 4: incompletas = 0 → set completo en todas las órdenes ✅
-- Query 4b: vacío → cada orden balancea exactamente con CLIENT_DEBT ✅
--           (Si Query 4b muestra órdenes = hay un bug real de contabilidad)
-- Query 5: SETTLEMENT_PAYMENT + SETTLEMENT_RECEPTION neto = $0 ✅
-- Query 7: pending = $0 → no hay deudas pendientes de cobro
--
-- ⚠️ POR QUÉ Query 3 antigua daba FALSO POSITIVO:
--   La versión anterior excluía CLIENT_DEBT y chequeaba delta = $0 por orden.
--   Pero CLIENT_DEBT ES la entrada que balancea cada orden de efectivo.
--   Sin CLIENT_DEBT, delta = total_order (ESPERADO, no es un error).
-- ============================================================================
