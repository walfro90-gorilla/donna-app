-- =====================================================================
-- Hard reset: dynamic commission_bps, proper descriptions, trigger cleanup
-- Why: Still seeing 20% PLATFORM_COMMISSION and NULL descriptions in feed.
-- This script:
--  - Drops legacy triggers/functions that may be overriding logic
--  - Replaces process_order_payment_v2() to use restaurants.commission_bps
--  - Inserts descriptions and metadata consistently
--  - Uses PLATFORM_DELIVERY_MARGIN for platform's delivery share
--  - Keeps Balance Cero intact (cash and card)
-- =====================================================================

-- 0) Ensure restaurants.commission_bps exists with sane bounds (0..3000 bps)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='restaurants' AND column_name='commission_bps'
  ) THEN
    ALTER TABLE public.restaurants ADD COLUMN commission_bps integer NOT NULL DEFAULT 1500;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname='public' AND t.relname='restaurants' AND c.conname='restaurants_commission_bps_check'
  ) THEN
    ALTER TABLE public.restaurants
      ADD CONSTRAINT restaurants_commission_bps_check
      CHECK (commission_bps >= 0 AND commission_bps <= 3000);
  END IF;
END $$;

-- Helper to render percent like 15%
CREATE OR REPLACE FUNCTION public._fmt_pct(p_rate numeric)
RETURNS text AS $$
BEGIN
  RETURN trim(trailing '.' FROM trim(trailing '0' FROM to_char(p_rate * 100, 'FM999999990.99'))) || '%';
END; $$ LANGUAGE plpgsql IMMUTABLE;

-- 1) Drop legacy triggers that could still be firing
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name='trigger_process_payment_on_delivery') THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trigger_process_payment_on_delivery ON public.orders';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name='trigger_order_financial_completion') THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trigger_order_financial_completion ON public.orders';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name='trigger_process_order_payment') THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trigger_process_order_payment ON public.orders';
  END IF;
END $$;

-- 2) Drop older functions that might conflict (safe if they don't exist)
DROP FUNCTION IF EXISTS public.process_order_payment();
DROP FUNCTION IF EXISTS public.trigger_process_order_completion();

-- 3) Create the authoritative v2 function
CREATE OR REPLACE FUNCTION public.process_order_payment_v2()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  restaurant_account_id uuid;
  delivery_agent_account_id uuid;
  platform_revenue_account_id uuid;
  platform_payables_account_id uuid;

  v_restaurant_user_id uuid;

  subtotal numeric;
  platform_commission numeric;
  delivery_earning numeric;
  platform_delivery_margin numeric;

  v_commission_bps integer;
  v_commission_rate numeric; -- 0.00 .. 0.30
  v_already boolean;
BEGIN
  -- Only act on first transition to delivered
  IF NEW.status = 'delivered' AND OLD.status <> 'delivered' THEN

    -- Idempotency: if there is already any PLATFORM_COMMISSION or ORDER_REVENUE for this order, skip
    SELECT EXISTS (
      SELECT 1 FROM public.account_transactions
      WHERE order_id = NEW.id AND type IN ('ORDER_REVENUE','PLATFORM_COMMISSION')
    ) INTO v_already;
    IF v_already THEN
      RETURN NEW;
    END IF;

    -- Resolve restaurant user and account
    SELECT r.user_id INTO v_restaurant_user_id
    FROM public.restaurants r
    WHERE r.id = NEW.restaurant_id;

    IF v_restaurant_user_id IS NULL THEN
      RAISE EXCEPTION 'Restaurant % has no user_id linked', NEW.restaurant_id;
    END IF;

    SELECT a.id INTO restaurant_account_id
    FROM public.accounts a
    WHERE a.user_id = v_restaurant_user_id AND a.account_type = 'restaurant'
    ORDER BY a.created_at ASC
    LIMIT 1;

    -- Delivery account (optional)
    IF NEW.delivery_agent_id IS NOT NULL THEN
      SELECT a.id INTO delivery_agent_account_id
      FROM public.accounts a
      WHERE a.user_id = NEW.delivery_agent_id AND a.account_type = 'delivery_agent'
      ORDER BY a.created_at ASC
      LIMIT 1;
    END IF;

    -- Platform accounts by account_type
    SELECT a.id INTO platform_revenue_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_revenue'
    ORDER BY a.created_at ASC
    LIMIT 1;

    SELECT a.id INTO platform_payables_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_payables'
    ORDER BY a.created_at ASC
    LIMIT 1;

    IF restaurant_account_id IS NULL OR platform_revenue_account_id IS NULL OR platform_payables_account_id IS NULL
       OR (NEW.delivery_agent_id IS NOT NULL AND delivery_agent_account_id IS NULL) THEN
      RAISE EXCEPTION 'Cuentas requeridas faltantes (rest:% del:% plat_rev:% plat_pay:%) para %',
        restaurant_account_id, delivery_agent_account_id, platform_revenue_account_id, platform_payables_account_id, NEW.id;
    END IF;

    -- Financials
    subtotal := NEW.total_amount - COALESCE(NEW.delivery_fee, 0);
    SELECT COALESCE(commission_bps, 1500) INTO v_commission_bps
    FROM public.restaurants WHERE id = NEW.restaurant_id;
    v_commission_rate := (COALESCE(v_commission_bps, 1500))::numeric / 10000.0;

    platform_commission := ROUND(subtotal * v_commission_rate, 2);
    delivery_earning := ROUND(COALESCE(NEW.delivery_fee, 0) * 0.85, 2);
    platform_delivery_margin := COALESCE(NEW.delivery_fee, 0) - delivery_earning;

    -- Cash vs Card flows
    IF NEW.payment_method = 'cash' THEN
      -- Restaurant revenue
      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        restaurant_account_id, 'ORDER_REVENUE', subtotal,
        'Ingreso por pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );

      -- Restaurant pays platform commission
      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission,
        format('Comisión %s - Pedido #%%s', public._fmt_pct(v_commission_rate))::text || NEW.id::text,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );

      -- Delivery earning
      IF delivery_agent_account_id IS NOT NULL THEN
        INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
        VALUES (
          delivery_agent_account_id, 'DELIVERY_EARNING', delivery_earning,
          'Ganancia delivery - Pedido #' || NEW.id,
          NEW.id,
          jsonb_build_object('delivery_fee', NEW.delivery_fee),
          NOW()
        );

        -- Collected cash (negative liability)
        INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, created_at)
        VALUES (
          delivery_agent_account_id, 'CASH_COLLECTED', -NEW.total_amount,
          'Efectivo recolectado - Pedido #' || NEW.id,
          NEW.id,
          NOW()
        );
      END IF;

      -- Platform commission
      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        platform_revenue_account_id, 'PLATFORM_COMMISSION', platform_commission,
        format('Comisión %s - Pedido #%%s', public._fmt_pct(v_commission_rate))::text || NEW.id::text,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );

      -- Platform delivery margin (explicit type per schema)
      IF platform_delivery_margin <> 0 THEN
        INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
        VALUES (
          platform_revenue_account_id, 'PLATFORM_DELIVERY_MARGIN', platform_delivery_margin,
          'Margen delivery - Pedido #' || NEW.id,
          NEW.id,
          jsonb_build_object('delivery_fee', NEW.delivery_fee),
          NOW()
        );
      END IF;
    ELSE
      -- Card flow
      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        restaurant_account_id, 'ORDER_REVENUE', subtotal,
        'Ingreso por pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );

      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission,
        format('Comisión %s - Pedido #%%s', public._fmt_pct(v_commission_rate))::text || NEW.id::text,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );

      IF delivery_agent_account_id IS NOT NULL THEN
        INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
        VALUES (
          delivery_agent_account_id, 'DELIVERY_EARNING', delivery_earning,
          'Ganancia delivery - Pedido #' || NEW.id,
          NEW.id,
          jsonb_build_object('delivery_fee', NEW.delivery_fee),
          NOW()
        );
      END IF;

      -- Platform receives card funds as payable (negative)
      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, created_at)
      VALUES (
        platform_payables_account_id, 'CASH_COLLECTED', -NEW.total_amount,
        'Dinero recibido por tarjeta - Pedido #' || NEW.id,
        NEW.id,
        NOW()
      );

      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        platform_revenue_account_id, 'PLATFORM_COMMISSION', platform_commission,
        format('Comisión %s - Pedido #%%s', public._fmt_pct(v_commission_rate))::text || NEW.id::text,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );
    END IF;

    -- Recompute balances for affected accounts using sum of transactions
    UPDATE public.accounts SET balance = (
      SELECT COALESCE(SUM(amount), 0) FROM public.account_transactions WHERE account_id = restaurant_account_id
    ) WHERE id = restaurant_account_id;

    IF delivery_agent_account_id IS NOT NULL THEN
      UPDATE public.accounts SET balance = (
        SELECT COALESCE(SUM(amount), 0) FROM public.account_transactions WHERE account_id = delivery_agent_account_id
      ) WHERE id = delivery_agent_account_id;
    END IF;

    UPDATE public.accounts SET balance = (
      SELECT COALESCE(SUM(amount), 0) FROM public.account_transactions WHERE account_id = platform_revenue_account_id
    ) WHERE id = platform_revenue_account_id;

    UPDATE public.accounts SET balance = (
      SELECT COALESCE(SUM(amount), 0) FROM public.account_transactions WHERE account_id = platform_payables_account_id
    ) WHERE id = platform_payables_account_id;
  END IF;

  RETURN NEW;
END;
$$;

-- 4) Create the canonical trigger pointing to v2
CREATE TRIGGER trigger_process_order_payment
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.process_order_payment_v2();

-- 5) Diagnostics helper: preview financials per order
CREATE OR REPLACE FUNCTION public.rpc_preview_order_financials(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_subtotal numeric;
  v_commission_bps integer;
  v_commission_rate numeric;
  v_commission numeric;
  v_delivery_earning numeric;
  v_platform_delivery_margin numeric;
BEGIN
  SELECT o.*, COALESCE(r.commission_bps, 1500) AS c_bps
  INTO v_order
  FROM public.orders o
  LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.id = p_order_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found');
  END IF;

  v_subtotal := COALESCE(v_order.total_amount,0) - COALESCE(v_order.delivery_fee,0);
  v_commission_bps := COALESCE(v_order.c_bps, 1500);
  v_commission_rate := v_commission_bps::numeric / 10000.0;
  v_commission := ROUND(v_subtotal * v_commission_rate, 2);
  v_delivery_earning := ROUND(COALESCE(v_order.delivery_fee, 0) * 0.85, 2);
  v_platform_delivery_margin := COALESCE(v_order.delivery_fee, 0) - v_delivery_earning;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'commission_bps', v_commission_bps,
    'commission_rate', v_commission_rate,
    'subtotal', v_subtotal,
    'commission', v_commission,
    'delivery_earning', v_delivery_earning,
    'platform_delivery_margin', v_platform_delivery_margin
  );
END; $$;

-- End of hard reset
