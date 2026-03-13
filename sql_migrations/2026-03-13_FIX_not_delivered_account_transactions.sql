-- ============================================================================
-- FIX: mark_order_not_delivered — Integración con account_transactions + settlements
-- Date: 2026-03-13
-- ============================================================================
-- Problema: El RPC original solo escribe en financial_transactions (ledger simple
-- por usuario). El sistema de doble entrada (account_transactions / Balance 0)
-- nunca se toca para órdenes no entregadas, dejando:
--   • Sin settlements formales para restaurante y repartidor
--   • Sin registro contable en el sistema principal
--
-- Este fix:
--   1. Agrega INSERTs en account_transactions (mismo patrón que process_order_delivery_v3)
--   2. Crea settlements pendientes (platform_payables → restaurant / delivery_agent)
--   3. Corrige bug: delivery agent recibía 100% del delivery_fee, ahora recibe 85%
--   4. Mantiene los INSERTs en financial_transactions para compatibilidad con la UI
--   5. Mantiene todo el sistema de client_debts y suspensiones intacto
--
-- A QUIÉN SE LE CARGA:
--   • RESTAURANTE: siempre cobra (preparó la comida de buena fe)
--   • REPARTIDOR: siempre cobra 85% del delivery_fee (hizo el viaje)
--   • PLATAFORMA: absorbe el costo temporalmente (paga a restaurant + delivery)
--   • CLIENTE: client_debt creada — si paga, la plataforma recupera; si no, es pérdida
-- ============================================================================

DROP FUNCTION IF EXISTS public.mark_order_not_delivered(uuid, uuid, text, text, text);

CREATE OR REPLACE FUNCTION public.mark_order_not_delivered(
  p_order_id          uuid,
  p_delivery_agent_id uuid,
  p_photo_url         text    DEFAULT NULL,
  p_delivery_notes    text    DEFAULT NULL,
  p_reason            text    DEFAULT 'not_delivered'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  -- Order data
  v_order_record          RECORD;
  v_debt_id               uuid;

  -- Amounts (recalculated via commission_bps, same as process_order_delivery_v3)
  v_subtotal              numeric(10,2);
  v_total_amount          numeric(10,2);
  v_delivery_fee          numeric(10,2);
  v_commission_bps        integer;
  v_commission_rate       numeric(10,4);
  v_platform_commission   numeric(10,2);
  v_restaurant_net        numeric(10,2);
  v_delivery_earning      numeric(10,2);   -- 85% of delivery_fee
  v_platform_delivery_margin numeric(10,2); -- 15% of delivery_fee

  -- Accounts (for account_transactions system)
  v_restaurant_account_id      uuid;
  v_delivery_account_id        uuid;
  v_platform_revenue_account_id uuid;
  v_platform_payables_account_id uuid;

  -- Suspension management
  v_client_suspension     RECORD;
  v_new_failed_attempts   int;
  v_should_suspend        boolean := false;
  v_short_order           text;
BEGIN
  -- ── 1. Obtain order info ───────────────────────────────────────────────────
  SELECT
    o.*,
    r.user_id        AS restaurant_owner_id,
    r.commission_bps AS restaurant_commission_bps
  INTO v_order_record
  FROM public.orders o
  LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.id = p_order_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found');
  END IF;

  -- ── 2. Validations ────────────────────────────────────────────────────────
  IF v_order_record.status NOT IN ('assigned', 'picked_up', 'on_the_way', 'in_transit') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Order must be in assigned, picked_up, on_the_way, or in_transit status'
    );
  END IF;

  IF v_order_record.delivery_agent_id != p_delivery_agent_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You are not the assigned delivery agent for this order'
    );
  END IF;

  -- ── 3. Calculate amounts (mirrors process_order_delivery_v3 exactly) ──────
  v_total_amount  := COALESCE(v_order_record.total_amount, 0);
  v_delivery_fee  := COALESCE(v_order_record.delivery_fee, 0);
  v_subtotal      := COALESCE(v_order_record.subtotal, v_total_amount - v_delivery_fee);

  v_commission_bps  := GREATEST(0, LEAST(3000, COALESCE(v_order_record.restaurant_commission_bps, 1500)));
  v_commission_rate := v_commission_bps / 10000.0;

  v_platform_commission      := ROUND(v_subtotal * v_commission_rate, 2);
  v_restaurant_net           := ROUND(v_subtotal - v_platform_commission, 2);
  v_delivery_earning         := ROUND(v_delivery_fee * 0.85, 2);     -- 85% to delivery agent
  v_platform_delivery_margin := ROUND(v_delivery_fee - v_delivery_earning, 2); -- 15% to platform

  v_short_order := LEFT(p_order_id::text, 8);

  -- ── 4. Update order status ────────────────────────────────────────────────
  UPDATE public.orders
  SET status = 'not_delivered', updated_at = now()
  WHERE id = p_order_id;

  -- ── 5. Create client debt record ──────────────────────────────────────────
  INSERT INTO public.client_debts (
    client_id, order_id, amount, reason, status, photo_url, delivery_notes
  ) VALUES (
    v_order_record.client_id,
    p_order_id,
    v_total_amount + v_delivery_fee,   -- Full amount client owes
    p_reason,
    'pending',
    p_photo_url,
    p_delivery_notes
  )
  RETURNING id INTO v_debt_id;

  -- ── 6. account_transactions (Balance 0 / double-entry system) ─────────────
  -- Resolve accounts
  SELECT a.id INTO v_restaurant_account_id
  FROM public.accounts a
  WHERE a.user_id = v_order_record.restaurant_owner_id AND a.account_type = 'restaurant'
  ORDER BY a.created_at DESC LIMIT 1;

  SELECT a.id INTO v_delivery_account_id
  FROM public.accounts a
  WHERE a.user_id = p_delivery_agent_id AND a.account_type = 'delivery_agent'
  ORDER BY a.created_at DESC LIMIT 1;

  SELECT a.id INTO v_platform_revenue_account_id
  FROM public.accounts a
  WHERE a.account_type = 'platform_revenue'
  ORDER BY a.created_at DESC LIMIT 1;

  SELECT a.id INTO v_platform_payables_account_id
  FROM public.accounts a
  WHERE a.account_type = 'platform_payables'
  ORDER BY a.created_at DESC LIMIT 1;

  -- Only proceed if core accounts exist (graceful degradation: won't fail if missing)
  IF v_platform_revenue_account_id IS NOT NULL AND v_platform_payables_account_id IS NOT NULL THEN

    -- 6a. ORDER_REVENUE — platform receives the order amount (same as delivered)
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
    VALUES (
      v_platform_payables_account_id,
      'ORDER_REVENUE',
      v_total_amount,
      p_order_id,
      'Orden no entregada #' || v_short_order,
      jsonb_build_object(
        'not_delivered', true,
        'reason', p_reason,
        'debt_id', v_debt_id,
        'payment_method', COALESCE(v_order_record.payment_method, 'cash'),
        'commission_bps', v_commission_bps
      )
    )
    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

    -- 6b. PLATFORM_COMMISSION — platform keeps its commission (food was prepared)
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
    VALUES (
      v_platform_revenue_account_id,
      'PLATFORM_COMMISSION',
      v_platform_commission,
      p_order_id,
      'Comisión plataforma ' || v_commission_bps || 'bps orden no entregada #' || v_short_order,
      jsonb_build_object(
        'not_delivered', true,
        'reason', p_reason,
        'commission_bps', v_commission_bps,
        'commission_rate', v_commission_rate,
        'subtotal', v_subtotal
      )
    )
    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

    -- 6c. RESTAURANT_PAYABLE — restaurant gets paid (prepared the food in good faith)
    IF v_restaurant_account_id IS NOT NULL AND v_restaurant_net > 0 THEN
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_restaurant_account_id,
        'RESTAURANT_PAYABLE',
        v_restaurant_net,
        p_order_id,
        'Pago restaurante orden no entregada #' || v_short_order || ' (plataforma absorbe)',
        jsonb_build_object(
          'not_delivered', true,
          'reason', p_reason,
          'paid_by_platform', true,
          'net_amount', v_restaurant_net
        )
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    END IF;

    -- 6d. DELIVERY_EARNING + PLATFORM_DELIVERY_MARGIN — delivery agent made the trip
    IF v_delivery_account_id IS NOT NULL AND v_delivery_fee > 0 THEN
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_delivery_account_id,
        'DELIVERY_EARNING',
        v_delivery_earning,
        p_order_id,
        'Ganancia repartidor 85% orden no entregada #' || v_short_order || ' (plataforma absorbe)',
        jsonb_build_object(
          'not_delivered', true,
          'reason', p_reason,
          'paid_by_platform', true,
          'delivery_percentage', 0.85,
          'delivery_fee', v_delivery_fee
        )
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_DELIVERY_MARGIN',
        v_platform_delivery_margin,
        p_order_id,
        'Margen delivery plataforma 15% orden no entregada #' || v_short_order,
        jsonb_build_object(
          'not_delivered', true,
          'reason', p_reason,
          'platform_percentage', 0.15,
          'delivery_fee', v_delivery_fee
        )
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    END IF;

    -- ── 7. Settlements (platform_payables → restaurant + delivery_agent) ─────
    -- Same as card payment delivered case: platform owes restaurant and delivery agent.
    -- (The client debt is how the platform eventually recovers this expenditure.)

    IF v_restaurant_account_id IS NOT NULL AND v_restaurant_net > 0 THEN
      INSERT INTO public.settlements (
        payer_account_id, receiver_account_id, amount,
        status, confirmation_code, initiated_at, notes
      ) VALUES (
        v_platform_payables_account_id,
        v_restaurant_account_id,
        v_restaurant_net,
        'pending',
        LPAD(FLOOR(RANDOM() * 10000)::text, 4, '0'),
        now(),
        'Orden no entregada #' || v_short_order || ' — ' || p_reason
      );
    END IF;

    IF v_delivery_account_id IS NOT NULL AND v_delivery_earning > 0 THEN
      INSERT INTO public.settlements (
        payer_account_id, receiver_account_id, amount,
        status, confirmation_code, initiated_at, notes
      ) VALUES (
        v_platform_payables_account_id,
        v_delivery_account_id,
        v_delivery_earning,
        'pending',
        LPAD(FLOOR(RANDOM() * 10000)::text, 4, '0'),
        now(),
        'Viaje no entregado #' || v_short_order || ' — ' || p_reason
      );
    END IF;

  END IF; -- end account_transactions block

  -- ── 8. financial_transactions (ledger simple — compatibilidad con UI) ──────
  -- Restaurant credit (fixed: now uses v_restaurant_net from commission_bps)
  INSERT INTO public.financial_transactions (
    user_id, order_id, transaction_type, amount, balance_after, description, metadata
  )
  SELECT
    v_order_record.restaurant_owner_id,
    p_order_id,
    'order_completed',
    v_restaurant_net,
    COALESCE(
      (SELECT balance_after FROM public.financial_transactions
       WHERE user_id = v_order_record.restaurant_owner_id
       ORDER BY created_at DESC LIMIT 1),
      0
    ) + v_restaurant_net,
    'Pago orden no entregada #' || p_order_id || ' (plataforma absorbe)',
    jsonb_build_object(
      'debt_id', v_debt_id,
      'paid_by_platform', true,
      'reason', p_reason,
      'not_delivered', true
    );

  -- Delivery agent credit (FIXED: 85% of delivery_fee, not 100%)
  INSERT INTO public.financial_transactions (
    user_id, order_id, transaction_type, amount, balance_after, description, metadata
  )
  SELECT
    p_delivery_agent_id,
    p_order_id,
    'delivery_completed',
    v_delivery_earning,
    COALESCE(
      (SELECT balance_after FROM public.financial_transactions
       WHERE user_id = p_delivery_agent_id
       ORDER BY created_at DESC LIMIT 1),
      0
    ) + v_delivery_earning,
    'Viaje no completado #' || p_order_id || ' (plataforma absorbe)',
    jsonb_build_object(
      'debt_id', v_debt_id,
      'paid_by_platform', true,
      'reason', p_reason,
      'delivery_percentage', 0.85,
      'not_delivered', true
    );

  -- ── 9. client_debts_transactions (audit trail) ────────────────────────────
  INSERT INTO public.client_debts_transactions (
    debt_id, client_id, amount, transaction_type, description
  ) VALUES (
    v_debt_id,
    v_order_record.client_id,
    v_total_amount + v_delivery_fee,
    'debt_created',
    'Adeudo por orden no entregada #' || p_order_id
  );

  -- ── 10. Account suspension management ────────────────────────────────────
  SELECT * INTO v_client_suspension
  FROM public.client_account_suspensions
  WHERE client_id = v_order_record.client_id
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.client_account_suspensions (
      client_id, failed_attempts, last_failed_order_id
    ) VALUES (v_order_record.client_id, 1, p_order_id);
    v_new_failed_attempts := 1;
  ELSE
    v_new_failed_attempts := v_client_suspension.failed_attempts + 1;

    IF v_new_failed_attempts >= 3 THEN
      v_should_suspend := true;
      UPDATE public.client_account_suspensions
      SET
        failed_attempts        = v_new_failed_attempts,
        is_suspended           = true,
        suspended_at           = now(),
        suspension_expires_at  = now() + interval '10 minutes',
        last_failed_order_id   = p_order_id,
        updated_at             = now()
      WHERE client_id = v_order_record.client_id;
    ELSE
      UPDATE public.client_account_suspensions
      SET
        failed_attempts      = v_new_failed_attempts,
        last_failed_order_id = p_order_id,
        updated_at           = now()
      WHERE client_id = v_order_record.client_id;
    END IF;
  END IF;

  -- ── 11. Return result ──────────────────────────────────────────────────────
  RETURN jsonb_build_object(
    'success',               true,
    'debt_id',               v_debt_id,
    'order_id',              p_order_id,
    'amount_owed',           v_total_amount + v_delivery_fee,
    'restaurant_paid',       v_restaurant_net,
    'delivery_agent_paid',   v_delivery_earning,
    'failed_attempts',       v_new_failed_attempts,
    'is_suspended',          v_should_suspend,
    'suspension_expires_at', CASE
      WHEN v_should_suspend THEN (now() + interval '10 minutes')::text
      ELSE NULL
    END
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   SQLERRM
    );
END;
$$;

-- ── Verify ────────────────────────────────────────────────────────────────────
-- After applying:
-- 1. Mark an order as not_delivered via the app
-- 2. Check account_transactions:
--    SELECT type, amount FROM account_transactions WHERE order_id = '<order_id>' ORDER BY type;
--    Should show: ORDER_REVENUE, PLATFORM_COMMISSION, RESTAURANT_PAYABLE, DELIVERY_EARNING, PLATFORM_DELIVERY_MARGIN
-- 3. Check settlements:
--    SELECT amount, status, notes FROM settlements ORDER BY initiated_at DESC LIMIT 5;
--    Should show 2 pending settlements (platform→restaurant, platform→delivery)
-- 4. Verify delivery agent gets 85% not 100%:
--    SELECT amount FROM account_transactions WHERE order_id = '<order_id>' AND type = 'DELIVERY_EARNING';
