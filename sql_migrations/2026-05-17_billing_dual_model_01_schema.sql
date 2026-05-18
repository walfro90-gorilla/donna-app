-- =============================================================================
-- BILLING DUAL MODEL - 01 SCHEMA
-- Introduce modelo dual de cobro: comisión por pedido vs. renta mensual fija.
--
-- Cambios:
--   1) platform_settings: keys nuevas (billing_mode + cuotas + grace)
--   2) orders: columnas snapshot (billing_mode, tip_amount)
--   3) Nueva tabla subscriptions   (una por cuenta restaurant/delivery)
--   4) Nueva tabla subscription_invoices (historial mensual)
--   5) RLS y políticas básicas
--
-- Idempotente. Compatible con modo actual (default 'commission').
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1) PLATFORM_SETTINGS: agregar keys del modo de cobro
-- =============================================================================

INSERT INTO public.platform_settings (key, value)
VALUES
  ('billing_mode', 'commission'),
  ('subscription_fee_restaurant', '999'),
  ('subscription_fee_delivery', '999'),
  ('subscription_grace_days', '7')
ON CONFLICT (key) DO NOTHING;

-- =============================================================================
-- 2) ORDERS: snapshot del modo + propina
-- =============================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS billing_mode text NOT NULL DEFAULT 'commission'
    CHECK (billing_mode IN ('commission','subscription'));

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tip_amount numeric(10,2) NOT NULL DEFAULT 0
    CHECK (tip_amount >= 0);

CREATE INDEX IF NOT EXISTS ix_orders_billing_mode ON public.orders(billing_mode);

-- =============================================================================
-- 3) TABLA: subscriptions
--    Una suscripción por cuenta (restaurant o delivery_agent).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.subscriptions (
  id                       uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id               uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  role                     text NOT NULL CHECK (role IN ('restaurant','delivery_agent')),
  monthly_fee              numeric(10,2) NOT NULL CHECK (monthly_fee >= 0),
  status                   text NOT NULL DEFAULT 'active'
                             CHECK (status IN ('active','past_due','suspended','cancelled')),
  current_period_start     timestamptz NOT NULL,
  current_period_end       timestamptz NOT NULL,
  last_paid_at             timestamptz,
  suspended_at             timestamptz,
  external_subscription_id text,           -- futuro MercadoPago Suscripciones
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT subscriptions_account_unique UNIQUE (account_id)
);

CREATE INDEX IF NOT EXISTS ix_subscriptions_status   ON public.subscriptions(status);
CREATE INDEX IF NOT EXISTS ix_subscriptions_role     ON public.subscriptions(role);
CREATE INDEX IF NOT EXISTS ix_subscriptions_period_end ON public.subscriptions(current_period_end);

-- =============================================================================
-- 4) TABLA: subscription_invoices
--    Una factura mensual por periodo de cada suscripción.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.subscription_invoices (
  id                  uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  subscription_id     uuid NOT NULL REFERENCES public.subscriptions(id) ON DELETE CASCADE,
  account_id          uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  period_start        timestamptz NOT NULL,
  period_end          timestamptz NOT NULL,
  amount              numeric(10,2) NOT NULL CHECK (amount >= 0),
  status              text NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','paid','overdue','waived','cancelled')),
  due_date            timestamptz NOT NULL,
  paid_at             timestamptz,
  paid_by_admin_id    uuid,
  payment_method      text,                -- 'spei' | 'mp_recurring' | 'admin_waive'
  payment_reference   text,
  notes               text,
  idempotency_key     text UNIQUE,         -- prep MP webhook
  external_invoice_id text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT subscription_invoices_period_unique UNIQUE (subscription_id, period_start)
);

CREATE INDEX IF NOT EXISTS ix_subscription_invoices_status_due
  ON public.subscription_invoices(status, due_date);
CREATE INDEX IF NOT EXISTS ix_subscription_invoices_account
  ON public.subscription_invoices(account_id);

-- =============================================================================
-- 5) TRIGGER: mantener updated_at en subscriptions
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_subscriptions_touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_subscriptions_touch_updated_at ON public.subscriptions;
CREATE TRIGGER trg_subscriptions_touch_updated_at
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.fn_subscriptions_touch_updated_at();

-- =============================================================================
-- 6) RLS - subscriptions
-- =============================================================================

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subscriptions_select_own ON public.subscriptions;
CREATE POLICY subscriptions_select_own ON public.subscriptions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.accounts a
      WHERE a.id = subscriptions.account_id AND a.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

DROP POLICY IF EXISTS subscriptions_admin_all ON public.subscriptions;
CREATE POLICY subscriptions_admin_all ON public.subscriptions
  FOR ALL TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin')
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin')
  );

-- =============================================================================
-- 7) RLS - subscription_invoices
-- =============================================================================

ALTER TABLE public.subscription_invoices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subscription_invoices_select_own ON public.subscription_invoices;
CREATE POLICY subscription_invoices_select_own ON public.subscription_invoices
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.accounts a
      WHERE a.id = subscription_invoices.account_id AND a.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

DROP POLICY IF EXISTS subscription_invoices_admin_all ON public.subscription_invoices;
CREATE POLICY subscription_invoices_admin_all ON public.subscription_invoices
  FOR ALL TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin')
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin')
  );

COMMIT;

-- =============================================================================
-- VERIFICACIÓN MANUAL (no se ejecuta):
--   SELECT key, value FROM platform_settings WHERE key LIKE 'billing%' OR key LIKE 'subscription%';
--   \d public.subscriptions
--   \d public.subscription_invoices
--   SELECT column_name FROM information_schema.columns
--     WHERE table_name='orders' AND column_name IN ('billing_mode','tip_amount');
-- =============================================================================
