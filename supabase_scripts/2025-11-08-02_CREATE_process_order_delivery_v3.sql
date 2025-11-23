-- Purpose: Single, idempotent financial processor for orders delivered.
-- Aligns strictly with supabase_scripts/DATABASE_SCHEMA.sql
-- - Uses restaurants.commission_bps (0..3000 bps)
-- - Writes account_transactions with description + metadata
-- - Creates pending settlements according to payment_method
-- - Single trigger on orders when status transitions to 'delivered'

BEGIN;

-- Ensure the unique constraint used for idempotency exists (no-op if already there)
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

-- Create/replace the unified v3 function
CREATE OR REPLACE FUNCTION public.process_order_delivery_v3()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  -- Commission vars
  v_commission_bps integer;
  v_commission_rate numeric(10,4);
  v_platform_commission numeric(10,2);
  v_restaurant_net numeric(10,2);
  v_delivery_earning numeric(10,2);
  v_platform_delivery_margin numeric(10,2);

  -- Accounts
  v_restaurant_account_id uuid;
  v_delivery_account_id uuid;
  v_platform_revenue_account_id uuid;
  v_platform_payables_account_id uuid;

  -- Other
  v_payment_method text;
  v_restaurant_user_id uuid;

  -- Settlements
  v_st_card_to_restaurant uuid;
  v_st_card_to_delivery uuid;
  v_st_cash_from_delivery uuid;

  v_short_order text := '';
BEGIN
  -- Fire only on delivered transition
  IF NEW.status = 'delivered' AND (OLD.status IS DISTINCT FROM 'delivered') THEN

    v_short_order := LEFT(NEW.id::text, 8);

    -- Idempotency guard: if ORDER_REVENUE already exists for this order, exit
    IF EXISTS (
      SELECT 1
      FROM public.account_transactions
      WHERE order_id = NEW.id AND type = 'ORDER_REVENUE'
    ) THEN
      RAISE NOTICE '⏭️  Order % already processed. Skipping.', NEW.id;
      RETURN NEW;
    END IF;

    -- Fetch restaurant config and user_id
    SELECT COALESCE(r.commission_bps, 1500), r.user_id
    INTO v_commission_bps, v_restaurant_user_id
    FROM public.restaurants r
    WHERE r.id = NEW.restaurant_id;

    IF v_restaurant_user_id IS NULL THEN
      RAISE WARNING 'Restaurant not found for order %', NEW.id;
      RETURN NEW;
    END IF;

    -- Clamp and compute rates
    v_commission_bps := GREATEST(0, LEAST(3000, v_commission_bps));
    v_commission_rate := v_commission_bps / 10000.0;

    -- Monetary computations using schema columns
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
      RAISE WARNING 'Missing core accounts (restaurant/platform) for order %', NEW.id;
      RETURN NEW;
    END IF;

    -- Optional payment record (safe insert only if not exists)
    PERFORM 1 FROM public.payments p WHERE p.order_id = NEW.id;
    IF NOT FOUND THEN
      INSERT INTO public.payments(order_id, amount, status, created_at)
      VALUES (NEW.id, NEW.total_amount, 'succeeded', now());
    END IF;

    -- Ledger entries (idempotent via unique constraint)
    -- 1) Gross order revenue captured by platform payables
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
    VALUES (
      v_platform_payables_account_id,
      'ORDER_REVENUE',
      NEW.total_amount,
      NEW.id,
      'Ingreso total orden #' || v_short_order,
      jsonb_build_object(
        'commission_bps', v_commission_bps,
        'commission_rate', v_commission_rate,
        'subtotal', COALESCE(NEW.subtotal, NEW.total_amount - COALESCE(NEW.delivery_fee, 0)),
        'delivery_fee', COALESCE(NEW.delivery_fee, 0),
        'payment_method', v_payment_method
      )
    )
    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

    -- 2) Platform commission to platform revenue
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
    VALUES (
      v_platform_revenue_account_id,
      'PLATFORM_COMMISSION',
      v_platform_commission,
      NEW.id,
      'Comisión plataforma ' || v_commission_bps || 'bps orden #' || v_short_order,
      jsonb_build_object(
        'commission_bps', v_commission_bps,
        'commission_rate', v_commission_rate,
        'subtotal', COALESCE(NEW.subtotal, NEW.total_amount - COALESCE(NEW.delivery_fee, 0)),
        'calculated_commission', v_platform_commission,
        'payment_method', v_payment_method
      )
    )
    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

    -- 3) Restaurant net payable
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
    VALUES (
      v_restaurant_account_id,
      'RESTAURANT_PAYABLE',
      v_restaurant_net,
      NEW.id,
      'Pago neto restaurante orden #' || v_short_order,
      jsonb_build_object(
        'commission_bps', v_commission_bps,
        'commission_rate', v_commission_rate,
        'subtotal', COALESCE(NEW.subtotal, NEW.total_amount - COALESCE(NEW.delivery_fee, 0)),
        'commission_deducted', v_platform_commission,
        'net_amount', v_restaurant_net,
        'payment_method', v_payment_method
      )
    )
    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

    -- 4) Delivery earning and platform margin
    IF v_delivery_account_id IS NOT NULL AND COALESCE(NEW.delivery_fee, 0) > 0 THEN
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_delivery_account_id,
        'DELIVERY_EARNING',
        v_delivery_earning,
        NEW.id,
        'Ganancia entrega 85% orden #' || v_short_order,
        jsonb_build_object(
          'delivery_fee', COALESCE(NEW.delivery_fee, 0),
          'delivery_percentage', 0.85,
          'calculated_earning', v_delivery_earning,
          'payment_method', v_payment_method
        )
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_DELIVERY_MARGIN',
        v_platform_delivery_margin,
        NEW.id,
        'Margen delivery plataforma 15% orden #' || v_short_order,
        jsonb_build_object(
          'delivery_fee', COALESCE(NEW.delivery_fee, 0),
          'platform_percentage', 0.15,
          'calculated_margin', v_platform_delivery_margin,
          'payment_method', v_payment_method
        )
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    END IF;

    -- 5) Cash collected (if applicable)
    IF v_payment_method = 'cash' AND v_delivery_account_id IS NOT NULL THEN
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_delivery_account_id,
        'CASH_COLLECTED',
        -NEW.total_amount,
        NEW.id,
        'Efectivo recolectado orden #' || v_short_order,
        jsonb_build_object(
          'total', NEW.total_amount,
          'collected_by_delivery', true,
          'payment_method', v_payment_method
        )
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    END IF;

    -- 6) Create pending settlements according to payment method
    IF v_payment_method = 'card' THEN
      -- Platform payables will settle restaurant net and delivery earning
      INSERT INTO public.settlements (payer_account_id, receiver_account_id, amount, status, confirmation_code, initiated_at, notes)
      VALUES (v_platform_payables_account_id, v_restaurant_account_id, v_restaurant_net, 'pending', LPAD(FLOOR(RANDOM()*10000)::text, 4, '0'), now(), 'Orden #' || v_short_order || ' (card)')
      RETURNING id INTO v_st_card_to_restaurant;

      IF v_delivery_account_id IS NOT NULL AND v_delivery_earning > 0 THEN
        INSERT INTO public.settlements (payer_account_id, receiver_account_id, amount, status, confirmation_code, initiated_at, notes)
        VALUES (v_platform_payables_account_id, v_delivery_account_id, v_delivery_earning, 'pending', LPAD(FLOOR(RANDOM()*10000)::text, 4, '0'), now(), 'Orden #' || v_short_order || ' (card)')
        RETURNING id INTO v_st_card_to_delivery;
      END IF;
    ELSE
      -- cash: delivery agent must settle total to platform payables
      IF v_delivery_account_id IS NOT NULL THEN
        INSERT INTO public.settlements (payer_account_id, receiver_account_id, amount, status, confirmation_code, initiated_at, initiated_by, notes)
        VALUES (v_delivery_account_id, v_platform_payables_account_id, NEW.total_amount, 'pending', LPAD(FLOOR(RANDOM()*10000)::text, 4, '0'), now(), NEW.delivery_agent_id, 'Orden #' || v_short_order || ' (cash)')
        RETURNING id INTO v_st_cash_from_delivery;
      END IF;
    END IF;

    RAISE NOTICE '✅ Entrega procesada: order %, commission_bps %, net_rest %, deliv %', NEW.id, v_commission_bps, v_restaurant_net, v_delivery_earning;
  END IF;

  RETURN NEW;
END;
$$;

-- Recreate a single trigger bound to delivered transition (lowercase per schema)
DROP TRIGGER IF EXISTS trg_on_order_delivered_process_v3 ON public.orders;
CREATE TRIGGER trg_on_order_delivered_process_v3
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'delivered')
EXECUTE FUNCTION public.process_order_delivery_v3();

COMMIT;
