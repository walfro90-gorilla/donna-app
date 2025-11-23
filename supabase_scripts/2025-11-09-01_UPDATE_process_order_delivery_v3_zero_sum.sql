-- Purpose: Permanent zero-sum fix for delivery processing (cash and card)
-- Strictly aligned with supabase_scripts/DATABASE_SCHEMA.sql
-- Key points:
--  - Removes any dependency on ORDER_REVENUE postings
--  - Ensures per-order SUM(account_transactions.amount) = 0
--  - Uses CASH_COLLECTED as the balancing line with metadata.payment_method
--  - Creates pending settlements appropriate to payment_method
--  - Idempotent via (order_id, account_id, type) unique constraint

BEGIN;

-- Ensure idempotency unique constraint exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND t.relname = 'account_transactions'
      AND c.conname = 'uq_account_txn_order_account_type'
  ) THEN
    EXECUTE 'ALTER TABLE public.account_transactions
             ADD CONSTRAINT uq_account_txn_order_account_type
             UNIQUE (order_id, account_id, type)';
  END IF;
END $$;

-- Create/replace v3 function with zero-sum and no ORDER_REVENUE
CREATE OR REPLACE FUNCTION public.process_order_delivery_v3()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_commission_bps integer;
  v_commission_rate numeric(10,4);
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

  v_settlement_id uuid;
  v_short_order text := '';
BEGIN
  IF NEW.status = 'delivered' AND (OLD.status IS DISTINCT FROM 'delivered') THEN
    v_short_order := LEFT(NEW.id::text, 8);

    -- Restaurant config
    SELECT COALESCE(r.commission_bps, 1500), r.user_id
    INTO v_commission_bps, v_restaurant_user_id
    FROM public.restaurants r
    WHERE r.id = NEW.restaurant_id;

    IF v_restaurant_user_id IS NULL THEN
      RAISE WARNING '[delivery_v3] Restaurant not found for order %', NEW.id;
      RETURN NEW;
    END IF;

    -- Clamp and compute amounts
    v_commission_bps := GREATEST(0, LEAST(3000, v_commission_bps));
    v_commission_rate := v_commission_bps / 10000.0;
    v_platform_commission := ROUND(COALESCE(NEW.subtotal, NEW.total_amount - COALESCE(NEW.delivery_fee, 0)) * v_commission_rate, 2);
    v_restaurant_net := ROUND(COALESCE(NEW.subtotal, NEW.total_amount - COALESCE(NEW.delivery_fee, 0)) - v_platform_commission, 2);
    v_delivery_earning := ROUND(COALESCE(NEW.delivery_fee, 0) * 0.85, 2);
    v_platform_delivery_margin := ROUND(COALESCE(NEW.delivery_fee, 0) - v_delivery_earning, 2);

    v_payment_method := COALESCE(NEW.payment_method, 'cash');

    -- Resolve accounts
    SELECT a.id INTO v_restaurant_account_id
    FROM public.accounts a
    WHERE a.user_id = v_restaurant_user_id AND a.account_type = 'restaurant'
    ORDER BY a.created_at DESC
    LIMIT 1;

    IF NEW.delivery_agent_id IS NOT NULL THEN
      SELECT a.id INTO v_delivery_account_id
      FROM public.accounts a
      WHERE a.user_id = NEW.delivery_agent_id AND a.account_type = 'delivery_agent'
      ORDER BY a.created_at DESC
      LIMIT 1;
    END IF;

    SELECT a.id INTO v_platform_revenue_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_revenue'
    ORDER BY a.created_at DESC
    LIMIT 1;

    SELECT a.id INTO v_platform_payables_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_payables'
    ORDER BY a.created_at DESC
    LIMIT 1;

    IF v_restaurant_account_id IS NULL OR v_platform_revenue_account_id IS NULL OR v_platform_payables_account_id IS NULL THEN
      RAISE WARNING '[delivery_v3] Missing core accounts for order %', NEW.id;
      RETURN NEW;
    END IF;

    -- Distribution lines (positives)
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
    VALUES (
      v_platform_revenue_account_id,
      'PLATFORM_COMMISSION',
      v_platform_commission,
      NEW.id,
      'Comisión plataforma ' || v_commission_bps || 'bps orden #' || v_short_order,
      jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', v_payment_method)
    )
    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
    VALUES (
      v_restaurant_account_id,
      'RESTAURANT_PAYABLE',
      v_restaurant_net,
      NEW.id,
      'Pago neto restaurante orden #' || v_short_order,
      jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', v_payment_method)
    )
    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

    IF v_delivery_account_id IS NOT NULL AND COALESCE(NEW.delivery_fee, 0) > 0 THEN
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_delivery_account_id,
        'DELIVERY_EARNING',
        v_delivery_earning,
        NEW.id,
        'Ganancia delivery 85% orden #' || v_short_order,
        jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.85, 'payment_method', v_payment_method)
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_DELIVERY_MARGIN',
        v_platform_delivery_margin,
        NEW.id,
        'Margen plataforma delivery 15% orden #' || v_short_order,
        jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.15, 'payment_method', v_payment_method)
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    END IF;

    -- Balancing line (negative) to make per-order sum = 0
    IF v_payment_method = 'cash' AND v_delivery_account_id IS NOT NULL THEN
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_delivery_account_id,
        'CASH_COLLECTED',
        -NEW.total_amount,
        NEW.id,
        'Efectivo recolectado orden #' || v_short_order,
        jsonb_build_object('total', NEW.total_amount, 'payment_method', 'cash', 'collected_by_delivery', true)
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    ELSE
      -- card: platform captured funds; post balancing negative in platform_payables
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_payables_account_id,
        'CASH_COLLECTED',
        -NEW.total_amount,
        NEW.id,
        'Cobro por tarjeta orden #' || v_short_order,
        jsonb_build_object('total', NEW.total_amount, 'payment_method', 'card')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    END IF;

    -- Create pending settlements
    IF v_payment_method = 'card' THEN
      -- platform payables -> restaurant (net)
      INSERT INTO public.settlements (payer_account_id, receiver_account_id, amount, status, confirmation_code, initiated_at, notes)
      VALUES (v_platform_payables_account_id, v_restaurant_account_id, v_restaurant_net, 'pending', LPAD(FLOOR(RANDOM()*10000)::text, 4, '0'), now(), 'Orden #' || v_short_order || ' (card → restaurant)')
      RETURNING id INTO v_settlement_id;

      -- platform payables -> delivery (earning)
      IF v_delivery_account_id IS NOT NULL AND v_delivery_earning > 0 THEN
        INSERT INTO public.settlements (payer_account_id, receiver_account_id, amount, status, confirmation_code, initiated_at, notes)
        VALUES (v_platform_payables_account_id, v_delivery_account_id, v_delivery_earning, 'pending', LPAD(FLOOR(RANDOM()*10000)::text, 4, '0'), now(), 'Orden #' || v_short_order || ' (card → delivery)')
        RETURNING id INTO v_settlement_id;
      END IF;
    ELSE
      -- cash: delivery → platform payables, for the net amount after keeping his earning
      IF v_delivery_account_id IS NOT NULL THEN
        INSERT INTO public.settlements (payer_account_id, receiver_account_id, amount, status, confirmation_code, initiated_at, initiated_by, notes)
        VALUES (v_delivery_account_id, v_platform_payables_account_id, (NEW.total_amount - v_delivery_earning), 'pending', LPAD(FLOOR(RANDOM()*10000)::text, 4, '0'), now(), NEW.delivery_agent_id, 'Orden #' || v_short_order || ' (cash → platform)')
        RETURNING id INTO v_settlement_id;
      END IF;
    END IF;

    RAISE NOTICE '✅ [delivery_v3] order % processed (method %, net_rest %, deliv %)', NEW.id, v_payment_method, v_restaurant_net, v_delivery_earning;
  END IF;

  RETURN NEW;
END;
$$;

-- Single trigger bound to delivered transition
DROP TRIGGER IF EXISTS trg_on_order_delivered_process_v3 ON public.orders;
CREATE TRIGGER trg_on_order_delivered_process_v3
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'delivered')
EXECUTE FUNCTION public.process_order_delivery_v3();

COMMIT;
