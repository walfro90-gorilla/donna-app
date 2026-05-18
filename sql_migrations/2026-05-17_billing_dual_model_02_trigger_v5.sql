-- =============================================================================
-- BILLING DUAL MODEL - 02 TRIGGER (v5)
-- Reemplaza process_order_delivery_v4() con branching por billing_mode.
--
-- Reglas:
--   - billing_mode='commission' → comportamiento idéntico al v4 actual
--     (PLATFORM_COMMISSION + PLATFORM_DELIVERY_MARGIN + splits 85/15)
--     + TIP_EARNING en card si tip_amount > 0
--   - billing_mode='subscription' → repartidor 100% delivery + 100% tip,
--     restaurante 100% subtotal, plataforma 0 del pedido.
--
-- Invariante: la suma de transacciones por order_id sigue siendo 0.
--
-- IMPORTANTE (fix 2026-05-18): NO usar NEW.subtotal — es columna GENERATED como
-- (total - delivery), que NO resta tip. Calculamos v_subtotal explícitamente
-- como (total - delivery - tip). De lo contrario el restaurante recibe subtotal+tip.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.process_order_delivery_v4()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_billing_mode text;
  v_tip_amount   numeric(10,2);

  v_commission_bps integer;
  v_commission_rate numeric(10,4);
  v_subtotal numeric(10,2);
  v_platform_commission numeric(10,2);
  v_restaurant_net numeric(10,2);
  v_delivery_earning numeric(10,2);
  v_platform_delivery_margin numeric(10,2);

  v_restaurant_account_id uuid;
  v_delivery_account_id uuid;
  v_platform_revenue_account_id uuid;
  v_platform_payables_account_id uuid;

  v_payment_method text;
  v_restaurant_user_id uuid;
  v_short_order text := '';
BEGIN
  IF NEW.status = 'delivered' AND (OLD.status IS DISTINCT FROM 'delivered') THEN
    v_short_order   := LEFT(NEW.id::text, 8);
    v_billing_mode  := COALESCE(NEW.billing_mode, 'commission');
    v_tip_amount    := COALESCE(NEW.tip_amount, 0);
    v_payment_method := COALESCE(NEW.payment_method, 'cash');

    -- Restaurant config
    SELECT COALESCE(r.commission_bps, 1500), r.user_id
    INTO v_commission_bps, v_restaurant_user_id
    FROM public.restaurants r
    WHERE r.id = NEW.restaurant_id;

    IF v_restaurant_user_id IS NULL THEN
      RAISE WARNING '[delivery_v5] Restaurant not found for order %', NEW.id;
      RETURN NEW;
    END IF;

    -- FIX 2026-05-18: subtotal explícito SIN usar NEW.subtotal
    -- (columna generada que no resta tip_amount; inflaría el ingreso del restaurante).
    v_subtotal := ROUND(
      GREATEST(
        COALESCE(NEW.total_amount, 0) - COALESCE(NEW.delivery_fee, 0) - v_tip_amount,
        0
      ), 2);

    -- Resolve accounts (idénticos al v4)
    SELECT a.id INTO v_restaurant_account_id
    FROM public.accounts a
    WHERE a.user_id = v_restaurant_user_id AND a.account_type = 'restaurant'
    ORDER BY a.created_at DESC LIMIT 1;

    IF NEW.delivery_agent_id IS NOT NULL THEN
      SELECT a.id INTO v_delivery_account_id
      FROM public.accounts a
      WHERE a.user_id = NEW.delivery_agent_id AND a.account_type = 'delivery_agent'
      ORDER BY a.created_at DESC LIMIT 1;
    END IF;

    SELECT a.id INTO v_platform_revenue_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_revenue'
    ORDER BY a.created_at DESC LIMIT 1;

    SELECT a.id INTO v_platform_payables_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_payables'
    ORDER BY a.created_at DESC LIMIT 1;

    IF v_restaurant_account_id IS NULL OR v_platform_revenue_account_id IS NULL OR v_platform_payables_account_id IS NULL THEN
      RAISE WARNING '[delivery_v5] Missing core accounts for order %', NEW.id;
      RETURN NEW;
    END IF;

    -- =========================================================================
    -- MODO COMMISSION (comportamiento histórico)
    -- =========================================================================
    IF v_billing_mode = 'commission' THEN
      v_commission_bps  := GREATEST(0, LEAST(3000, v_commission_bps));
      v_commission_rate := v_commission_bps / 10000.0;
      -- App price = kitchen_price * (1 + rate); commission = subtotal * rate / (1 + rate)
      v_platform_commission := ROUND(v_subtotal * v_commission_rate / (1 + v_commission_rate), 2);
      v_restaurant_net      := ROUND(v_subtotal - v_platform_commission, 2);
      v_delivery_earning    := ROUND(COALESCE(NEW.delivery_fee, 0) * 0.85, 2);
      v_platform_delivery_margin := ROUND(COALESCE(NEW.delivery_fee, 0) - v_delivery_earning, 2);

      IF v_payment_method = 'card' THEN
        -- 6 transacciones zero-sum (MP cobra todo)
        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_platform_revenue_account_id, 'PLATFORM_COMMISSION', v_platform_commission, NEW.id,
          'Comisión plataforma ' || v_commission_bps || 'bps orden #' || v_short_order,
          jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'card', 'billing_mode', 'commission')
        ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_platform_revenue_account_id, 'PLATFORM_DELIVERY_MARGIN', v_platform_delivery_margin, NEW.id,
          'Margen plataforma delivery 15% orden #' || v_short_order,
          jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.15, 'payment_method', 'card', 'billing_mode', 'commission')
        ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_platform_payables_account_id, 'RESTAURANT_PAYABLE', -v_restaurant_net, NEW.id,
          'Deuda con restaurante orden #' || v_short_order,
          jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'card', 'billing_mode', 'commission')
        ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_restaurant_account_id, 'RESTAURANT_PAYABLE', v_restaurant_net, NEW.id,
          'Pago neto restaurante orden #' || v_short_order,
          jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'card', 'billing_mode', 'commission')
        ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

        IF v_delivery_account_id IS NOT NULL AND COALESCE(NEW.delivery_fee, 0) > 0 THEN
          INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
          VALUES (
            v_platform_payables_account_id, 'DELIVERY_EARNING', -v_delivery_earning, NEW.id,
            'Deuda con repartidor orden #' || v_short_order,
            jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.85, 'payment_method', 'card', 'billing_mode', 'commission')
          ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

          INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
          VALUES (
            v_delivery_account_id, 'DELIVERY_EARNING', v_delivery_earning, NEW.id,
            'Ganancia delivery 85% orden #' || v_short_order,
            jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.85, 'payment_method', 'card', 'billing_mode', 'commission')
          ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
        END IF;

        -- Propina (card): 100% al repartidor, espejo en payables
        IF v_delivery_account_id IS NOT NULL AND v_tip_amount > 0 THEN
          INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
          VALUES (
            v_platform_payables_account_id, 'TIP_EARNING', -v_tip_amount, NEW.id,
            'Propina a repartidor (espejo) orden #' || v_short_order,
            jsonb_build_object('tip_amount', v_tip_amount, 'payment_method', 'card', 'billing_mode', 'commission')
          ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

          INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
          VALUES (
            v_delivery_account_id, 'TIP_EARNING', v_tip_amount, NEW.id,
            'Propina recibida orden #' || v_short_order,
            jsonb_build_object('tip_amount', v_tip_amount, 'payment_method', 'card', 'billing_mode', 'commission')
          ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
        END IF;

      ELSE
        -- CASH commission: 5 transacciones zero-sum
        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_platform_revenue_account_id, 'PLATFORM_COMMISSION', v_platform_commission, NEW.id,
          'Comisión plataforma ' || v_commission_bps || 'bps orden #' || v_short_order,
          jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'cash', 'billing_mode', 'commission')
        ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_platform_revenue_account_id, 'PLATFORM_DELIVERY_MARGIN', v_platform_delivery_margin, NEW.id,
          'Margen plataforma delivery 15% orden #' || v_short_order,
          jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.15, 'payment_method', 'cash', 'billing_mode', 'commission')
        ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_restaurant_account_id, 'RESTAURANT_PAYABLE', v_restaurant_net, NEW.id,
          'Pago neto restaurante orden #' || v_short_order,
          jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'cash', 'billing_mode', 'commission')
        ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

        IF v_delivery_account_id IS NOT NULL AND COALESCE(NEW.delivery_fee, 0) > 0 THEN
          INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
          VALUES (
            v_delivery_account_id, 'DELIVERY_EARNING', v_delivery_earning, NEW.id,
            'Ganancia delivery 85% orden #' || v_short_order,
            jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.85, 'payment_method', 'cash', 'billing_mode', 'commission')
          ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

          INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
          VALUES (
            v_delivery_account_id, 'CASH_COLLECTED', -(v_subtotal + COALESCE(NEW.delivery_fee, 0)), NEW.id,
            'Efectivo recolectado orden #' || v_short_order,
            jsonb_build_object('total', v_subtotal + COALESCE(NEW.delivery_fee, 0), 'payment_method', 'cash', 'billing_mode', 'commission')
          ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
        END IF;
        -- Tip en cash: cliente paga directo al repartidor, no entra al ledger.
      END IF;

    -- =========================================================================
    -- MODO SUBSCRIPTION
    --   Plataforma no toca el pedido: solo cobra cuota mensual aparte.
    --   Repartidor recibe 100% delivery_fee + 100% tip.
    --   Restaurante recibe 100% subtotal.
    -- =========================================================================
    ELSE
      v_restaurant_net   := v_subtotal;
      v_delivery_earning := COALESCE(NEW.delivery_fee, 0);

      IF v_payment_method = 'card' THEN
        -- Restaurante: +subtotal / espejo -subtotal en platform_payables
        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_platform_payables_account_id, 'RESTAURANT_PAYABLE', -v_restaurant_net, NEW.id,
          'Deuda con restaurante (sub) orden #' || v_short_order,
          jsonb_build_object('payment_method', 'card', 'billing_mode', 'subscription')
        ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_restaurant_account_id, 'RESTAURANT_PAYABLE', v_restaurant_net, NEW.id,
          'Pago íntegro restaurante orden #' || v_short_order,
          jsonb_build_object('payment_method', 'card', 'billing_mode', 'subscription')
        ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

        -- Repartidor: +delivery_fee / espejo -delivery_fee
        IF v_delivery_account_id IS NOT NULL AND v_delivery_earning > 0 THEN
          INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
          VALUES (
            v_platform_payables_account_id, 'DELIVERY_EARNING', -v_delivery_earning, NEW.id,
            'Deuda con repartidor (sub) orden #' || v_short_order,
            jsonb_build_object('delivery_fee', v_delivery_earning, 'pct', 1.0, 'payment_method', 'card', 'billing_mode', 'subscription')
          ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

          INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
          VALUES (
            v_delivery_account_id, 'DELIVERY_EARNING', v_delivery_earning, NEW.id,
            'Ganancia delivery 100% orden #' || v_short_order,
            jsonb_build_object('delivery_fee', v_delivery_earning, 'pct', 1.0, 'payment_method', 'card', 'billing_mode', 'subscription')
          ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
        END IF;

        -- Tip: 100% al repartidor / espejo
        IF v_delivery_account_id IS NOT NULL AND v_tip_amount > 0 THEN
          INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
          VALUES (
            v_platform_payables_account_id, 'TIP_EARNING', -v_tip_amount, NEW.id,
            'Propina a repartidor (espejo) orden #' || v_short_order,
            jsonb_build_object('tip_amount', v_tip_amount, 'payment_method', 'card', 'billing_mode', 'subscription')
          ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

          INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
          VALUES (
            v_delivery_account_id, 'TIP_EARNING', v_tip_amount, NEW.id,
            'Propina recibida orden #' || v_short_order,
            jsonb_build_object('tip_amount', v_tip_amount, 'payment_method', 'card', 'billing_mode', 'subscription')
          ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
        END IF;

      ELSE
        -- CASH subscription: repartidor cobra todo, debe subtotal al restaurante.
        -- Suma zero-sum por orden:
        --   +subtotal restaurante
        --   +delivery_fee repartidor
        --   -(subtotal + delivery_fee) repartidor (CASH_COLLECTED)
        --   Tip cash directo cliente→repartidor, fuera del ledger.
        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_restaurant_account_id, 'RESTAURANT_PAYABLE', v_restaurant_net, NEW.id,
          'Pago íntegro restaurante orden #' || v_short_order,
          jsonb_build_object('payment_method', 'cash', 'billing_mode', 'subscription')
        ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

        IF v_delivery_account_id IS NOT NULL THEN
          IF v_delivery_earning > 0 THEN
            INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
            VALUES (
              v_delivery_account_id, 'DELIVERY_EARNING', v_delivery_earning, NEW.id,
              'Ganancia delivery 100% orden #' || v_short_order,
              jsonb_build_object('delivery_fee', v_delivery_earning, 'pct', 1.0, 'payment_method', 'cash', 'billing_mode', 'subscription')
            ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
          END IF;

          INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
          VALUES (
            v_delivery_account_id, 'CASH_COLLECTED',
            -(v_restaurant_net + v_delivery_earning), NEW.id,
            'Efectivo recolectado orden #' || v_short_order,
            jsonb_build_object('total', v_restaurant_net + v_delivery_earning, 'payment_method', 'cash', 'billing_mode', 'subscription')
          ) ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
        END IF;
      END IF;

    END IF;

    -- ── Recalcular balances de cuentas afectadas ────────────────────────────
    UPDATE public.accounts
    SET
      balance    = (SELECT COALESCE(SUM(amount), 0) FROM public.account_transactions WHERE account_id = accounts.id),
      updated_at = now()
    WHERE id IN (
      v_restaurant_account_id,
      v_delivery_account_id,
      v_platform_revenue_account_id,
      v_platform_payables_account_id
    );

    RAISE NOTICE '[delivery_v5] order % done (mode=%, method=%, subtotal=%, deliv=%, tip=%)',
      NEW.id, v_billing_mode, v_payment_method, v_subtotal, v_delivery_earning, v_tip_amount;
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger ya existe como trg_on_order_delivered_process_v4; no se redefine.
-- CREATE OR REPLACE de la función basta para que el trigger ejecute la nueva lógica.

COMMIT;
