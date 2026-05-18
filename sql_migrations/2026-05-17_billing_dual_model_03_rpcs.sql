-- =============================================================================
-- BILLING DUAL MODEL - 03 RPCS
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1) rpc_get_billing_mode()
--    Devuelve modo + cuotas + días de gracia. Cualquier usuario autenticado.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_get_billing_mode()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode        text;
  v_fee_rest    numeric(10,2);
  v_fee_deliv   numeric(10,2);
  v_grace       integer;
BEGIN
  SELECT value INTO v_mode      FROM public.platform_settings WHERE key = 'billing_mode';
  SELECT value::numeric INTO v_fee_rest  FROM public.platform_settings WHERE key = 'subscription_fee_restaurant';
  SELECT value::numeric INTO v_fee_deliv FROM public.platform_settings WHERE key = 'subscription_fee_delivery';
  SELECT value::integer INTO v_grace     FROM public.platform_settings WHERE key = 'subscription_grace_days';

  RETURN jsonb_build_object(
    'mode',                       COALESCE(v_mode, 'commission'),
    'subscription_fee_restaurant', COALESCE(v_fee_rest, 999),
    'subscription_fee_delivery',   COALESCE(v_fee_deliv, 999),
    'grace_days',                  COALESCE(v_grace, 7)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_billing_mode() TO authenticated;

-- =============================================================================
-- 2) rpc_admin_set_billing_mode(p_mode)
--    Cambia el modo global. Solo admin.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_admin_set_billing_mode(p_mode text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_user_id AND role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not an admin');
  END IF;

  IF p_mode NOT IN ('commission', 'subscription') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid mode (use commission or subscription)');
  END IF;

  INSERT INTO public.platform_settings (key, value, updated_at, updated_by)
  VALUES ('billing_mode', p_mode, now(), v_user_id)
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value,
        updated_at = now(),
        updated_by = v_user_id;

  RETURN jsonb_build_object('success', true, 'mode', p_mode);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_admin_set_billing_mode(text) TO authenticated;

-- =============================================================================
-- 3) rpc_create_subscription_for_account(p_account_id, p_role)
--    Crea la suscripción + primera invoice pendiente. Idempotente.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_create_subscription_for_account(
  p_account_id uuid,
  p_role       text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing       uuid;
  v_subscription_id uuid;
  v_fee            numeric(10,2);
  v_grace_days     integer;
  v_period_start   timestamptz := now();
  v_period_end     timestamptz;
  v_due_date       timestamptz;
  v_invoice_id     uuid;
BEGIN
  IF p_role NOT IN ('restaurant', 'delivery_agent') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid role');
  END IF;

  -- Idempotencia: si ya existe, devolverla.
  SELECT id INTO v_existing FROM public.subscriptions WHERE account_id = p_account_id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'subscription_id', v_existing, 'created', false);
  END IF;

  -- Lee cuota desde platform_settings (fallback hardcoded 999 si falta).
  IF p_role = 'restaurant' THEN
    SELECT COALESCE(value::numeric, 999) INTO v_fee
      FROM public.platform_settings WHERE key = 'subscription_fee_restaurant';
  ELSE
    SELECT COALESCE(value::numeric, 999) INTO v_fee
      FROM public.platform_settings WHERE key = 'subscription_fee_delivery';
  END IF;
  v_fee := COALESCE(v_fee, 999);

  SELECT COALESCE(value::integer, 7) INTO v_grace_days
    FROM public.platform_settings WHERE key = 'subscription_grace_days';
  v_grace_days := COALESCE(v_grace_days, 7);

  v_period_end := v_period_start + INTERVAL '1 month';
  v_due_date   := v_period_end;  -- la invoice vence al final del periodo

  INSERT INTO public.subscriptions (
    account_id, role, monthly_fee, status,
    current_period_start, current_period_end
  ) VALUES (
    p_account_id, p_role, v_fee, 'active',
    v_period_start, v_period_end
  )
  RETURNING id INTO v_subscription_id;

  INSERT INTO public.subscription_invoices (
    subscription_id, account_id, period_start, period_end, amount, status, due_date
  ) VALUES (
    v_subscription_id, p_account_id, v_period_start, v_period_end, v_fee, 'pending', v_due_date
  )
  RETURNING id INTO v_invoice_id;

  RETURN jsonb_build_object(
    'success', true,
    'subscription_id', v_subscription_id,
    'invoice_id', v_invoice_id,
    'created', true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_create_subscription_for_account(uuid, text) TO authenticated;

-- =============================================================================
-- 4) rpc_admin_bootstrap_subscriptions()
--    Crea suscripciones para todas las cuentas restaurant/delivery_agent que aún
--    no tienen. Útil al activar modo subscription por primera vez. Solo admin.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_admin_bootstrap_subscriptions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_count_created integer := 0;
  rec record;
  v_result jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_user_id AND role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not an admin');
  END IF;

  FOR rec IN
    SELECT a.id AS account_id, a.account_type
    FROM public.accounts a
    WHERE a.account_type IN ('restaurant', 'delivery_agent')
      AND NOT EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.account_id = a.id)
  LOOP
    v_result := public.rpc_create_subscription_for_account(rec.account_id, rec.account_type);
    IF (v_result ->> 'success')::boolean AND (v_result ->> 'created')::boolean THEN
      v_count_created := v_count_created + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'created', v_count_created);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_admin_bootstrap_subscriptions() TO authenticated;

-- =============================================================================
-- 5) rpc_admin_mark_invoice_paid(p_invoice_id, p_method, p_reference, p_notes)
--    Marca paid + actualiza suscripción + registra par zero-sum en ledger.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_admin_mark_invoice_paid(
  p_invoice_id uuid,
  p_method     text DEFAULT 'spei',
  p_reference  text DEFAULT NULL,
  p_notes      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
  v_invoice public.subscription_invoices%ROWTYPE;
  v_sub     public.subscriptions%ROWTYPE;
  v_platform_revenue_id uuid;
  v_platform_payables_id uuid;
  v_short_inv text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_admin_id AND role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not an admin');
  END IF;

  SELECT * INTO v_invoice FROM public.subscription_invoices WHERE id = p_invoice_id;
  IF v_invoice.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invoice not found');
  END IF;
  IF v_invoice.status IN ('paid', 'waived', 'cancelled') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invoice not in payable state', 'status', v_invoice.status);
  END IF;

  SELECT * INTO v_sub FROM public.subscriptions WHERE id = v_invoice.subscription_id;

  SELECT a.id INTO v_platform_revenue_id  FROM public.accounts a WHERE a.account_type = 'platform_revenue'  ORDER BY a.created_at DESC LIMIT 1;
  SELECT a.id INTO v_platform_payables_id FROM public.accounts a WHERE a.account_type = 'platform_payables' ORDER BY a.created_at DESC LIMIT 1;

  IF v_platform_revenue_id IS NULL OR v_platform_payables_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Missing platform accounts');
  END IF;

  v_short_inv := LEFT(v_invoice.id::text, 8);

  -- Par zero-sum: ingreso de la plataforma + contraparte en payables (origen externo SPEI/MP).
  INSERT INTO public.account_transactions(account_id, type, amount, order_id, settlement_id, description, metadata)
  VALUES (
    v_platform_revenue_id, 'SUBSCRIPTION_FEE', v_invoice.amount, NULL, NULL,
    'Cuota mensual cobrada inv #' || v_short_inv,
    jsonb_build_object(
      'invoice_id', v_invoice.id,
      'subscription_id', v_invoice.subscription_id,
      'account_id', v_invoice.account_id,
      'method', p_method,
      'reference', p_reference,
      'period_start', v_invoice.period_start,
      'period_end',   v_invoice.period_end
    )
  );

  INSERT INTO public.account_transactions(account_id, type, amount, order_id, settlement_id, description, metadata)
  VALUES (
    v_platform_payables_id, 'SUBSCRIPTION_FEE', -v_invoice.amount, NULL, NULL,
    'Cuota mensual (espejo) inv #' || v_short_inv,
    jsonb_build_object(
      'invoice_id', v_invoice.id,
      'method', p_method,
      'reference', p_reference
    )
  );

  UPDATE public.accounts
  SET balance = (SELECT COALESCE(SUM(amount), 0) FROM public.account_transactions WHERE account_id = accounts.id),
      updated_at = now()
  WHERE id IN (v_platform_revenue_id, v_platform_payables_id);

  UPDATE public.subscription_invoices
  SET status = 'paid',
      paid_at = now(),
      paid_by_admin_id = v_admin_id,
      payment_method = p_method,
      payment_reference = p_reference,
      notes = COALESCE(p_notes, notes)
  WHERE id = p_invoice_id;

  UPDATE public.subscriptions
  SET last_paid_at = now(),
      status = 'active',
      suspended_at = NULL
  WHERE id = v_sub.id;

  RETURN jsonb_build_object('success', true, 'invoice_id', p_invoice_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_admin_mark_invoice_paid(uuid, text, text, text) TO authenticated;

-- =============================================================================
-- 6) rpc_admin_waive_invoice(p_invoice_id, p_notes)
--    Perdona la invoice. No toca ledger. Reactiva la suscripción si estaba past_due.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_admin_waive_invoice(
  p_invoice_id uuid,
  p_notes      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
  v_invoice public.subscription_invoices%ROWTYPE;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_admin_id AND role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not an admin');
  END IF;

  SELECT * INTO v_invoice FROM public.subscription_invoices WHERE id = p_invoice_id;
  IF v_invoice.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invoice not found');
  END IF;
  IF v_invoice.status IN ('paid', 'waived', 'cancelled') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invoice not in waivable state', 'status', v_invoice.status);
  END IF;

  UPDATE public.subscription_invoices
  SET status = 'waived',
      paid_by_admin_id = v_admin_id,
      payment_method = 'admin_waive',
      notes = COALESCE(p_notes, notes)
  WHERE id = p_invoice_id;

  UPDATE public.subscriptions
  SET status = 'active', suspended_at = NULL
  WHERE id = v_invoice.subscription_id AND status IN ('past_due', 'suspended');

  RETURN jsonb_build_object('success', true, 'invoice_id', p_invoice_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_admin_waive_invoice(uuid, text) TO authenticated;

-- =============================================================================
-- 7) rpc_admin_extend_grace(p_subscription_id, p_extra_days, p_notes)
--    Extiende el due_date de la invoice pendiente más reciente.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_admin_extend_grace(
  p_subscription_id uuid,
  p_extra_days      integer,
  p_notes           text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
  v_invoice_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_admin_id AND role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not an admin');
  END IF;
  IF p_extra_days IS NULL OR p_extra_days <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'extra_days must be positive');
  END IF;

  SELECT id INTO v_invoice_id
  FROM public.subscription_invoices
  WHERE subscription_id = p_subscription_id
    AND status IN ('pending', 'overdue')
  ORDER BY period_start DESC
  LIMIT 1;

  IF v_invoice_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No active invoice to extend');
  END IF;

  UPDATE public.subscription_invoices
  SET due_date = due_date + (p_extra_days || ' days')::interval,
      status = CASE WHEN status = 'overdue' THEN 'pending' ELSE status END,
      notes  = COALESCE(p_notes, notes)
  WHERE id = v_invoice_id;

  UPDATE public.subscriptions
  SET status = 'active', suspended_at = NULL
  WHERE id = p_subscription_id AND status IN ('past_due', 'suspended');

  RETURN jsonb_build_object('success', true, 'invoice_id', v_invoice_id, 'extra_days', p_extra_days);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_admin_extend_grace(uuid, integer, text) TO authenticated;

-- =============================================================================
-- 8) rpc_get_my_subscription_status()
--    Devuelve el estado de la suscripción del usuario autenticado (restaurant o delivery).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_get_my_subscription_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_sub jsonb;
  v_next_invoice jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT to_jsonb(s) INTO v_sub
  FROM public.subscriptions s
  JOIN public.accounts a ON a.id = s.account_id
  WHERE a.user_id = v_user_id
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF v_sub IS NULL THEN
    RETURN jsonb_build_object('success', true, 'has_subscription', false);
  END IF;

  SELECT to_jsonb(i) INTO v_next_invoice
  FROM public.subscription_invoices i
  WHERE i.subscription_id = (v_sub ->> 'id')::uuid
    AND i.status IN ('pending', 'overdue')
  ORDER BY i.due_date ASC
  LIMIT 1;

  RETURN jsonb_build_object(
    'success', true,
    'has_subscription', true,
    'subscription', v_sub,
    'next_invoice', v_next_invoice
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_my_subscription_status() TO authenticated;

-- =============================================================================
-- 9) rpc_admin_list_subscriptions(p_role, p_status, p_limit, p_offset)
--    Listado paginado para el panel de admin.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_admin_list_subscriptions(
  p_role   text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_limit  integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
  v_rows jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_admin_id AND role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not an admin');
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_jsonb(t)), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT
      s.id, s.account_id, s.role, s.monthly_fee, s.status,
      s.current_period_start, s.current_period_end,
      s.last_paid_at, s.suspended_at, s.created_at,
      a.user_id,
      u.name      AS user_name,
      u.email     AS user_email,
      r.name      AS restaurant_name,
      (SELECT COUNT(*) FROM public.subscription_invoices i
        WHERE i.subscription_id = s.id AND i.status IN ('pending','overdue')) AS open_invoices,
      (SELECT MIN(due_date) FROM public.subscription_invoices i
        WHERE i.subscription_id = s.id AND i.status IN ('pending','overdue')) AS next_due_date
    FROM public.subscriptions s
    JOIN public.accounts a ON a.id = s.account_id
    LEFT JOIN public.users u ON u.id = a.user_id
    LEFT JOIN public.restaurants r ON r.user_id = a.user_id
    WHERE (p_role IS NULL OR s.role = p_role)
      AND (p_status IS NULL OR s.status = p_status)
    ORDER BY s.created_at DESC
    LIMIT GREATEST(p_limit, 1)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN jsonb_build_object('success', true, 'subscriptions', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_admin_list_subscriptions(text, text, integer, integer) TO authenticated;

-- =============================================================================
-- 10) rpc_admin_list_invoices_for_subscription(p_subscription_id)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_admin_list_invoices_for_subscription(
  p_subscription_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid := auth.uid();
  v_rows jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_admin_id AND role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not an admin');
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_jsonb(i) ORDER BY i.period_start DESC), '[]'::jsonb) INTO v_rows
  FROM public.subscription_invoices i
  WHERE i.subscription_id = p_subscription_id;

  RETURN jsonb_build_object('success', true, 'invoices', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_admin_list_invoices_for_subscription(uuid) TO authenticated;

COMMIT;
