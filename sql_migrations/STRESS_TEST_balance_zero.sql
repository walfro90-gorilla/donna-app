-- ============================================================================
-- STRESS TEST: Balance 0 — Todos los escenarios posibles
-- Doña Repartos | Ejecutar en Supabase Dashboard → SQL Editor
--
-- PREREQUISITOS:
--   1. SETUP_platform_accounts.sql ya ejecutado ✅
--   2. Al menos 1 restaurante aprobado en la DB
--   3. Al menos 1 delivery agent aprobado en la DB
--   4. Al menos 1 cliente en la DB
--
-- CÓMO USAR:
--   Ejecuta cada bloque por separado (selecciona y corre).
--   Verifica el balance después de cada escenario.
-- ============================================================================

-- ============================================================================
-- BLOQUE 0: INSPECCIÓN — ver con qué datos contamos
-- ============================================================================

-- 0a. Balance inicial (debe ser $0.00 o tu estado actual)
SELECT
  account_type,
  COUNT(*)                          AS cuentas,
  ROUND(SUM(balance)::numeric, 2)   AS total_balance
FROM public.accounts
GROUP BY account_type
ORDER BY account_type;

-- 0b. Usuarios disponibles para prueba
SELECT
  id,
  email,
  name,
  role
FROM public.users
WHERE role IN ('client', 'restaurant', 'delivery_agent', 'admin')
ORDER BY role;

-- 0c. Restaurantes disponibles
SELECT
  r.id          AS restaurant_id,
  r.name,
  r.commission_bps,
  r.delivery_fee,
  u.id          AS owner_user_id,
  u.email
FROM public.restaurants r
JOIN public.users u ON u.id = r.user_id
WHERE r.status = 'approved'
LIMIT 5;

-- 0d. Cuentas de plataforma (deben existir antes de cualquier prueba)
SELECT
  account_type,
  id AS account_id,
  balance,
  user_id
FROM public.accounts
WHERE account_type IN ('platform_revenue', 'platform_payables');


-- ============================================================================
-- BLOQUE 1: ESCENARIO — Orden entregada EFECTIVO (cash)
-- Resultado esperado: 6 transacciones, delta orden = $0 (con CLIENT_DEBT)
-- ============================================================================

-- ── 1a. CREAR orden de prueba — ajusta los UUIDs con los de Bloque 0 ─────────
-- ⚠️ Sustituye: CLIENT_UUID, RESTAURANT_UUID, DELIVERY_UUID con valores reales
/*
INSERT INTO public.orders (
  user_id, restaurant_id, delivery_agent_id,
  status, total_amount, subtotal, delivery_fee,
  payment_method, delivery_address
) VALUES (
  'CLIENT_UUID',
  'RESTAURANT_UUID',
  'DELIVERY_UUID',
  'on_the_way',         -- status válido para luego marcar como delivered
  110.00,               -- total_amount (subtotal + delivery_fee)
  100.00,               -- subtotal
  10.00,                -- delivery_fee
  'cash',
  'Calle de Prueba 123, Colonia Test'
)
RETURNING id AS order_id_cash;
*/

-- ── 1b. DISPARAR el trigger — cambiar status a 'delivered' ───────────────────
-- ⚠️ Sustituye ORDER_UUID_CASH con el id retornado en 1a
/*
UPDATE public.orders
SET status = 'delivered', updated_at = NOW()
WHERE id = 'ORDER_UUID_CASH';
*/

-- ── 1c. VERIFICAR transacciones de esta orden ────────────────────────────────
-- ⚠️ Sustituye ORDER_UUID_CASH
/*
SELECT
  at2.type,
  ROUND(at2.amount::numeric, 2)  AS amount,
  a.account_type,
  at2.description
FROM public.account_transactions at2
LEFT JOIN public.accounts a ON a.id = at2.account_id
WHERE at2.order_id = 'ORDER_UUID_CASH'
ORDER BY at2.type;
*/
-- Esperado: 6 filas (ORDER_REVENUE, RESTAURANT_PAYABLE, DELIVERY_EARNING,
--           PLATFORM_COMMISSION, PLATFORM_DELIVERY_MARGIN, CASH_COLLECTED)
-- Ninguna con account_id = NULL

-- ── 1d. VERIFICAR delta de la orden ─────────────────────────────────────────
-- ⚠️ Sustituye ORDER_UUID_CASH
/*
SELECT
  ROUND(SUM(amount)::numeric, 2)  AS delta_total,
  COUNT(*)                        AS num_txs,
  STRING_AGG(DISTINCT type, ', ' ORDER BY type) AS tipos
FROM public.account_transactions
WHERE order_id = 'ORDER_UUID_CASH';
*/
-- Esperado: delta_total = $0.00, num_txs = 6

-- ── 1e. BALANCE GLOBAL post-orden cash ──────────────────────────────────────
SELECT
  ROUND(SUM(balance)::numeric, 2) AS balance_global,
  CASE WHEN ABS(SUM(balance)) < 0.01 THEN '✅ OK' ELSE '🚨 DESBALANCE' END AS estado
FROM public.accounts;


-- ============================================================================
-- BLOQUE 2: ESCENARIO — Orden entregada TARJETA (card)
-- Resultado esperado: 5 transacciones (sin CASH_COLLECTED), delta ≠ $0 sin offset MP
-- ============================================================================

-- ── 2a. CREAR orden de prueba con pago card ──────────────────────────────────
/*
INSERT INTO public.orders (
  user_id, restaurant_id, delivery_agent_id,
  status, total_amount, subtotal, delivery_fee,
  payment_method, delivery_address
) VALUES (
  'CLIENT_UUID',
  'RESTAURANT_UUID',
  'DELIVERY_UUID',
  'on_the_way',
  220.00,    -- total
  200.00,    -- subtotal
  20.00,     -- delivery_fee
  'card',
  'Calle de Prueba 456, Colonia Test'
)
RETURNING id AS order_id_card;
*/

-- ── 2b. DISPARAR el trigger ──────────────────────────────────────────────────
/*
UPDATE public.orders
SET status = 'delivered', updated_at = NOW()
WHERE id = 'ORDER_UUID_CARD';
*/

-- ── 2c. VERIFICAR transacciones ─────────────────────────────────────────────
/*
SELECT
  at2.type,
  ROUND(at2.amount::numeric, 2) AS amount,
  a.account_type
FROM public.account_transactions at2
LEFT JOIN public.accounts a ON a.id = at2.account_id
WHERE at2.order_id = 'ORDER_UUID_CARD'
ORDER BY at2.type;
*/
-- Esperado: 5 filas (sin CASH_COLLECTED)
-- SUM de las 5 = +total_amount (el offset llega con webhook de MercadoPago)


-- ============================================================================
-- BLOQUE 3: ESCENARIO — Orden NO ENTREGADA
-- Resultado esperado: 5 transacciones que suman $0, + client_debt creada
-- ============================================================================

-- ── 3a. CREAR orden de prueba ────────────────────────────────────────────────
/*
INSERT INTO public.orders (
  user_id, restaurant_id, delivery_agent_id,
  status, total_amount, subtotal, delivery_fee,
  payment_method, delivery_address
) VALUES (
  'CLIENT_UUID',
  'RESTAURANT_UUID',
  'DELIVERY_UUID',
  'on_the_way',
  150.00,
  130.00,
  20.00,
  'cash',
  'Dirección Prueba No Entregado 789'
)
RETURNING id AS order_id_nd;
*/

-- ── 3b. LLAMAR al RPC mark_order_not_delivered ───────────────────────────────
/*
SELECT public.mark_order_not_delivered(
  'ORDER_UUID_ND'::uuid,
  'DELIVERY_UUID'::uuid,
  NULL,               -- photo_url (opcional)
  'Cliente no abrió', -- delivery_notes
  'not_delivered'     -- reason
);
*/
-- Esperado: { success: true, debt_id: "...", amount_owed: 150.00, ... }

-- ── 3c. VERIFICAR transacciones ─────────────────────────────────────────────
/*
SELECT
  at2.type,
  ROUND(at2.amount::numeric, 2) AS amount,
  a.account_type
FROM public.account_transactions at2
LEFT JOIN public.accounts a ON a.id = at2.account_id
WHERE at2.order_id = 'ORDER_UUID_ND'
ORDER BY at2.type;
*/
-- Esperado:
--   ORDER_REVENUE            platform_payables   -150.00  ← negativo (plataforma absorbe)
--   RESTAURANT_PAYABLE       restaurant          +110.50  ← subtotal * (1 - commission%)
--   DELIVERY_EARNING         delivery_agent       +17.00  ← delivery_fee * 0.85
--   PLATFORM_COMMISSION      platform_revenue     +19.50  ← subtotal * commission%
--   PLATFORM_DELIVERY_MARGIN platform_revenue      +3.00  ← delivery_fee * 0.15
--   SUM = $0.00 ✅

-- ── 3d. VERIFICAR client_debt creada ────────────────────────────────────────
/*
SELECT
  cd.id,
  cd.amount,
  cd.status,
  cd.reason,
  u.email AS cliente
FROM public.client_debts cd
JOIN public.users u ON u.id = cd.client_id
WHERE cd.order_id = 'ORDER_UUID_ND';
*/
-- Esperado: 1 fila, amount = 150.00, status = 'pending'

-- ── 3e. BALANCE GLOBAL post-no-entregado ─────────────────────────────────────
SELECT
  ROUND(SUM(balance)::numeric, 2) AS balance_global,
  CASE WHEN ABS(SUM(balance)) < 0.01 THEN '✅ OK' ELSE '🚨 DESBALANCE' END AS estado
FROM public.accounts;


-- ============================================================================
-- BLOQUE 4: ESCENARIO — Settlement completado (repartidor paga a restaurante)
-- Resultado esperado: SETTLEMENT_PAYMENT + SETTLEMENT_RECEPTION se cancelan
-- ============================================================================

-- ── 4a. Ver settlements pendientes ──────────────────────────────────────────
SELECT
  s.id,
  ROUND(s.amount::numeric, 2)    AS amount,
  s.status,
  s.confirmation_code,
  pa.account_type                AS payer,
  ra.account_type                AS receiver,
  s.notes
FROM public.settlements s
JOIN public.accounts pa ON pa.id = s.payer_account_id
JOIN public.accounts ra ON ra.id = s.receiver_account_id
WHERE s.status = 'pending'
ORDER BY s.initiated_at DESC
LIMIT 10;

-- ── 4b. COMPLETAR un settlement ──────────────────────────────────────────────
-- Usa el RPC real de la app o actualiza directamente para la prueba:
/*
UPDATE public.settlements
SET status = 'completed', completed_at = NOW()
WHERE id = 'SETTLEMENT_UUID';
*/
-- NOTA: el trigger de settlements crea SETTLEMENT_PAYMENT y SETTLEMENT_RECEPTION
-- en account_transactions. Si no hay trigger, el balance no cambia aquí.

-- ── 4c. Verificar transacciones de settlement ────────────────────────────────
/*
SELECT
  at2.type,
  ROUND(at2.amount::numeric, 2) AS amount,
  a.account_type
FROM public.account_transactions at2
LEFT JOIN public.accounts a ON a.id = at2.account_id
WHERE at2.settlement_id = 'SETTLEMENT_UUID'
ORDER BY at2.type;
*/


-- ============================================================================
-- BLOQUE 5: AUDITORÍA FINAL COMPLETA
-- Corre esto después de todos los escenarios anteriores
-- ============================================================================

-- 5a. Balance global
SELECT
  ROUND(SUM(balance)::numeric, 2) AS balance_global,
  CASE WHEN ABS(SUM(balance)) < 0.01
       THEN '✅ SISTEMA BALANCEADO'
       ELSE '🚨 DESBALANCE: $' || ABS(ROUND(SUM(balance)::numeric, 2))
  END AS estado
FROM public.accounts;

-- 5b. Balance por tipo de cuenta
SELECT
  account_type,
  COUNT(*)                          AS cuentas,
  ROUND(SUM(balance)::numeric, 2)   AS total_balance
FROM public.accounts
GROUP BY account_type
ORDER BY account_type;

-- 5c. Órdenes con tipos de transacción faltantes (debe estar vacío)
SELECT
  at2.order_id,
  COUNT(DISTINCT at2.type)         AS tipos_presentes,
  STRING_AGG(DISTINCT at2.type, ', ' ORDER BY at2.type) AS tipos,
  CASE
    WHEN NOT BOOL_OR(at2.type = 'ORDER_REVENUE')           THEN '❌ falta ORDER_REVENUE'
    WHEN NOT BOOL_OR(at2.type = 'RESTAURANT_PAYABLE')      THEN '❌ falta RESTAURANT_PAYABLE'
    WHEN NOT BOOL_OR(at2.type = 'DELIVERY_EARNING')        THEN '❌ falta DELIVERY_EARNING'
    WHEN NOT BOOL_OR(at2.type = 'PLATFORM_COMMISSION')     THEN '❌ falta PLATFORM_COMMISSION'
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
ORDER BY tipos_presentes ASC;
-- Esperado: 0 filas ✅

-- 5d. Transacciones huérfanas (account_id = NULL)
SELECT
  type,
  ROUND(amount::numeric, 2) AS amount,
  order_id,
  created_at
FROM public.account_transactions
WHERE account_id IS NULL
ORDER BY created_at DESC;
-- Esperado: 0 filas ✅ (si hay filas → SETUP_platform_accounts.sql no se corrió)

-- 5e. Delta por orden incluyendo CLIENT_DEBT (debe ser $0 por orden)
SELECT
  order_id,
  ROUND(SUM(amount)::numeric, 2)  AS delta,
  COUNT(*)                        AS num_txs,
  STRING_AGG(DISTINCT type, ', ' ORDER BY type) AS tipos
FROM public.account_transactions
WHERE order_id IS NOT NULL
GROUP BY order_id
HAVING ABS(SUM(amount)) > 0.01
ORDER BY ABS(SUM(amount)) DESC;
-- Esperado: 0 filas ✅

-- 5f. Resumen de tipos de transacción
SELECT
  type,
  COUNT(*)                          AS num_txs,
  ROUND(SUM(amount)::numeric, 2)    AS total_amount
FROM public.account_transactions
GROUP BY type
ORDER BY ABS(SUM(amount)) DESC;
