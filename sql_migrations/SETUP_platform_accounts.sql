-- ============================================================================
-- SETUP: Cuentas de Plataforma — Doña Repartos
-- Ejecutar UNA SOLA VEZ al inicializar la base de datos (o tras limpiarla).
-- Sin estas cuentas, las transacciones de ORDER_REVENUE y PLATFORM_COMMISSION
-- quedan con account_id = NULL (huérfanas) y rompen el Balance 0 visual.
--
-- DISEÑO: El trigger encuentra las cuentas de plataforma por account_type,
-- NO por user_id. Por eso las cuentas pueden tener user_id = NULL.
-- No se crean usuarios virtuales — evita el FK a auth.users.
--
-- ⚠️  NO incluye triggers ni lógica de negocio — solo crea los registros base.
-- ============================================================================

-- ── PASO 1: Verificar constraint de account_type ──────────────────────────────
-- El schema actual ya incluye platform_revenue y platform_payables.
-- Este bloque es defensivo: si por alguna razón el constraint fue reemplazado
-- por una versión anterior, lo restablece con todos los tipos válidos.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'accounts_account_type_check'
      AND conrelid = 'public.accounts'::regclass
      AND pg_get_constraintdef(oid) NOT LIKE '%platform_revenue%'
  ) THEN
    ALTER TABLE public.accounts DROP CONSTRAINT accounts_account_type_check;
    ALTER TABLE public.accounts
      ADD CONSTRAINT accounts_account_type_check
      CHECK (account_type IN (
        'client',
        'restaurant',
        'delivery_agent',
        'admin',
        'platform',
        'platform_revenue',
        'platform_payables'
      ));
    RAISE NOTICE '✅ Constraint accounts_account_type_check actualizado con tipos de plataforma';
  ELSE
    RAISE NOTICE 'ℹ️ Constraint accounts_account_type_check ya incluye platform_revenue — sin cambios';
  END IF;
END;
$$;

-- ── PASO 2: Crear cuentas de plataforma (sin user_id) ─────────────────────────
-- El trigger las busca por account_type, así que user_id = NULL es válido.
-- WHERE NOT EXISTS garantiza idempotencia (seguro re-ejecutar).

INSERT INTO public.accounts (account_type, balance, created_at, updated_at)
SELECT 'platform_revenue', 0.00, NOW(), NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM public.accounts WHERE account_type = 'platform_revenue'
);

INSERT INTO public.accounts (account_type, balance, created_at, updated_at)
SELECT 'platform_payables', 0.00, NOW(), NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM public.accounts WHERE account_type = 'platform_payables'
);

-- ── PASO 3: Verificación ──────────────────────────────────────────────────────
SELECT
  account_type,
  id          AS account_id,
  balance,
  user_id,
  '✅ Cuenta OK' AS estado
FROM public.accounts
WHERE account_type IN ('platform_revenue', 'platform_payables')
ORDER BY account_type;

-- ── PASO 4: Balance global (debe ser $0.00 con DB limpia) ────────────────────
SELECT
  ROUND(SUM(balance)::numeric, 2) AS balance_global,
  CASE WHEN ABS(SUM(balance)) < 0.01
       THEN '✅ SISTEMA LISTO'
       ELSE '⚠️ Hay balance previo: revisar transacciones'
  END AS estado
FROM public.accounts;
