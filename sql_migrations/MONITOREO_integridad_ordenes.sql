-- ============================================================================
-- MONITOREO DE INTEGRIDAD — Sistema Balance 0 — Doña Repartos
-- Ejecutar periódicamente en Supabase Dashboard → SQL Editor
-- Detecta anomalías contables en órdenes, cuentas y settlements
-- ============================================================================

-- ── 1) VERIFICACIÓN RÁPIDA: ¿Todo sigue en $0? ──────────────────────────────
SELECT
  ROUND(SUM(balance)::numeric, 2)  AS balance_global,
  COUNT(*)                         AS total_cuentas,
  CASE WHEN ABS(SUM(balance)) < 0.01
       THEN '✅ OK'
       ELSE '🚨 ALERTA: DESBALANCE DE $' || ABS(ROUND(SUM(balance)::numeric, 2))
  END AS estado
FROM public.accounts;

-- ── 2) ÓRDENES ENTREGADAS SIN TRANSACCIONES (huérfanas) ─────────────────────
--    Órdenes marcadas como delivered/not_delivered pero sin account_transactions.
SELECT
  o.id          AS order_id,
  o.status,
  o.total_amount,
  o.payment_method,
  o.created_at
FROM public.orders o
WHERE o.status IN ('delivered', 'not_delivered')
  AND NOT EXISTS (
    SELECT 1 FROM public.account_transactions at2
    WHERE at2.order_id = o.id
  )
ORDER BY o.created_at DESC
LIMIT 20;

-- ── 3) TRANSACCIONES DUPLICADAS POR ORDEN ───────────────────────────────────
--    Detecta si el guard de unicidad (uq_account_txn_order_account_type) falló.
SELECT
  order_id,
  type,
  account_id,
  COUNT(*)  AS veces
FROM public.account_transactions
WHERE order_id IS NOT NULL
GROUP BY order_id, type, account_id
HAVING COUNT(*) > 1
ORDER BY veces DESC;

-- ── 4) SETTLEMENTS PENDIENTES VIEJOS (> 7 días sin completar) ───────────────
--    Un settlement pendiente por más de 7 días puede indicar falta de liquidación.
SELECT
  s.id,
  s.amount,
  s.status,
  s.initiated_at,
  NOW() - s.initiated_at    AS tiempo_pendiente,
  pa.account_type           AS pagador_tipo,
  ra.account_type           AS receptor_tipo
FROM public.settlements s
JOIN public.accounts pa ON pa.id = s.payer_account_id
JOIN public.accounts ra ON ra.id = s.receiver_account_id
WHERE s.status = 'pending'
  AND s.initiated_at < NOW() - INTERVAL '7 days'
ORDER BY s.initiated_at ASC;

-- ── 5) DEUDAS DE CLIENTES POR ESTADO ────────────────────────────────────────
--    Muestra el universo de deudas. pending > 30 días = riesgo de pérdida.
SELECT
  status,
  COUNT(*)                          AS num_deudas,
  ROUND(SUM(amount)::numeric, 2)    AS total,
  MIN(created_at)                   AS mas_antigua,
  MAX(created_at)                   AS mas_reciente
FROM public.client_debts
GROUP BY status
ORDER BY status;

-- ── 6) DEUDAS PENDIENTES > 30 DÍAS ──────────────────────────────────────────
SELECT
  cd.id,
  cd.amount,
  cd.reason,
  cd.created_at,
  NOW() - cd.created_at  AS edad,
  u.name                 AS cliente,
  u.phone
FROM public.client_debts cd
JOIN public.users u ON u.id = cd.client_id
WHERE cd.status = 'pending'
  AND cd.created_at < NOW() - INTERVAL '30 days'
ORDER BY cd.created_at ASC;

-- ── 7) SALUD POR TIPO DE CUENTA (detalle) ────────────────────────────────────
--    Identifica qué cuentas individuales tienen balances anómalos.
SELECT
  a.account_type,
  u.name,
  u.email,
  ROUND(a.balance::numeric, 2)  AS balance,
  CASE
    WHEN a.account_type = 'platform_revenue'  AND a.balance < 0   THEN '⚠️ Revenue negativo'
    WHEN a.account_type = 'platform_payables' AND a.balance > 0   THEN '⚠️ Payables positivo (raro)'
    WHEN a.account_type = 'delivery_agent'    AND a.balance < -50 THEN '⚠️ Deuda alta repartidor'
    WHEN a.account_type = 'restaurant'        AND a.balance < -500 THEN '⚠️ Restaurante muy negativo'
    ELSE '✅ Normal'
  END AS alerta
FROM public.accounts a
JOIN public.users u ON u.id = a.user_id
ORDER BY a.account_type, a.balance ASC;

-- ── 8) CONCILIACIÓN POR ORDEN: delta incluye CLIENT_DEBT ────────────────────
--    Debe ser $0 por orden cuando se incluye CLIENT_DEBT.
--    Si hay resultados → bug real de contabilidad.
SELECT
  order_id,
  ROUND(SUM(amount)::numeric, 2)  AS delta,
  COUNT(*)                         AS num_txs,
  STRING_AGG(DISTINCT type, ', ' ORDER BY type) AS tipos
FROM public.account_transactions
WHERE order_id IS NOT NULL
GROUP BY order_id
HAVING ABS(SUM(amount)) > 0.01
ORDER BY ABS(SUM(amount)) DESC
LIMIT 20;

-- ============================================================================
-- RESUMEN DE USO:
--   Query 1: chequeo diario rápido
--   Query 2: órdenes huérfanas → trigger no disparó
--   Query 3: duplicados → unicidad comprometida
--   Query 4: settlements viejos → repartidores sin liquidar
--   Query 5-6: deudas clientes → riesgo financiero
--   Query 7: alertas por cuenta individual
--   Query 8: conciliación profunda → debe estar vacía siempre
-- ============================================================================
