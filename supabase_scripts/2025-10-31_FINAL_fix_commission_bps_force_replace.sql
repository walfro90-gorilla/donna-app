-- =====================================================================
-- FINAL: Force-replace ALL payment triggers/functions - use commission_bps
-- Context: Transaction feed still shows 20% flat & NULL description/metadata
-- Root cause: Old function process_order_payment_on_delivery still running
-- Solution: Nuclear drop of ALL legacy triggers/functions + recreate clean
-- =====================================================================

-- 1) DROP ALL triggers on orders (nuclear)
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (
    SELECT tgname FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'orders'
  ) LOOP
    EXECUTE 'DROP TRIGGER IF EXISTS ' || quote_ident(r.tgname) || ' ON public.orders CASCADE';
  END LOOP;
END $$;

-- 2) DROP ALL payment-related functions (CASCADE to kill any remaining triggers)
DROP FUNCTION IF EXISTS public.process_order_payment_on_delivery() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment_v2() CASCADE;

-- 3) Ensure commission_bps column and constraints exist
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

-- 4) Helper to format percentage like "15%"
CREATE OR REPLACE FUNCTION public._fmt_pct(p_rate numeric)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN trim(trailing '.' FROM trim(trailing '0' FROM to_char(p_rate * 100, 'FM999999990.99'))) || '%';
END;
$$;

-- 5) Create the ONE TRUE payment function using commission_bps
CREATE OR REPLACE FUNCTION public.process_order_payment_v2()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
  v_commission_rate numeric;
  v_already boolean;
BEGIN
  -- Only act when order transitions to 'delivered'
  IF NEW.status = 'delivered' AND OLD.status <> 'delivered' THEN

    -- Idempotency: skip if already posted
    SELECT EXISTS (
      SELECT 1 FROM public.account_transactions
      WHERE order_id = NEW.id AND type IN ('ORDER_REVENUE','PLATFORM_COMMISSION')
    ) INTO v_already;
    
    IF v_already THEN
      RETURN NEW;
    END IF;

    -- Get restaurant user
    SELECT r.user_id INTO v_restaurant_user_id
    FROM public.restaurants r
    WHERE r.id = NEW.restaurant_id;

    IF v_restaurant_user_id IS NULL THEN
      RAISE EXCEPTION 'Restaurant % has no linked user_id', NEW.restaurant_id;
    END IF;

    -- Get restaurant account
    SELECT a.id INTO restaurant_account_id
    FROM public.accounts a
    WHERE a.user_id = v_restaurant_user_id AND a.account_type = 'restaurant'
    ORDER BY a.created_at ASC
    LIMIT 1;

    -- Get delivery account (if assigned)
    IF NEW.delivery_agent_id IS NOT NULL THEN
      SELECT a.id INTO delivery_agent_account_id
      FROM public.accounts a
      WHERE a.user_id = NEW.delivery_agent_id AND a.account_type = 'delivery_agent'
      ORDER BY a.created_at ASC
      LIMIT 1;
    END IF;

    -- Get platform accounts
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

    -- Validate all required accounts exist
    IF restaurant_account_id IS NULL OR platform_revenue_account_id IS NULL OR platform_payables_account_id IS NULL
       OR (NEW.delivery_agent_id IS NOT NULL AND delivery_agent_account_id IS NULL) THEN
      RAISE EXCEPTION 'Missing required accounts (rest:% del:% plat_rev:% plat_pay:%) for order %',
        restaurant_account_id, delivery_agent_account_id, platform_revenue_account_id, platform_payables_account_id, NEW.id;
    END IF;

    -- Calculate financials using commission_bps from restaurants table
    subtotal := NEW.total_amount - COALESCE(NEW.delivery_fee, 0);
    
    -- Read commission_bps from restaurant, default 1500 (15%), clamp 0..3000 (0..30%)
    SELECT GREATEST(0, LEAST(COALESCE(commission_bps, 1500), 3000)) INTO v_commission_bps
    FROM public.restaurants WHERE id = NEW.restaurant_id;
    
    -- Convert basis points to rate: 1500 bps = 0.15
    v_commission_rate := v_commission_bps::numeric / 10000.0;

    platform_commission := ROUND(subtotal * v_commission_rate, 2);
    delivery_earning := ROUND(COALESCE(NEW.delivery_fee, 0) * 0.85, 2);
    platform_delivery_margin := COALESCE(NEW.delivery_fee, 0) - delivery_earning;

    -- Branch by payment method
    IF NEW.payment_method = 'cash' THEN
      -- CASH FLOW

      -- Restaurant receives order revenue
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
        'Comisión ' || public._fmt_pct(v_commission_rate) || ' - Pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );

      -- Delivery agent earnings
      IF delivery_agent_account_id IS NOT NULL THEN
        INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
        VALUES (
          delivery_agent_account_id, 'DELIVERY_EARNING', delivery_earning,
          'Ganancia delivery - Pedido #' || NEW.id,
          NEW.id,
          jsonb_build_object('delivery_fee', NEW.delivery_fee, 'rate', 0.85),
          NOW()
        );

        -- Delivery collects cash (negative liability)
        INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
        VALUES (
          delivery_agent_account_id, 'CASH_COLLECTED', -NEW.total_amount,
          'Efectivo recolectado - Pedido #' || NEW.id,
          NEW.id,
          jsonb_build_object('total_amount', NEW.total_amount),
          NOW()
        );
      END IF;

      -- Platform receives commission
      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        platform_revenue_account_id, 'PLATFORM_COMMISSION', platform_commission,
        'Comisión ' || public._fmt_pct(v_commission_rate) || ' - Pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );

      -- Platform delivery margin
      IF platform_delivery_margin <> 0 THEN
        INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
        VALUES (
          platform_revenue_account_id, 'PLATFORM_DELIVERY_MARGIN', platform_delivery_margin,
          'Margen delivery - Pedido #' || NEW.id,
          NEW.id,
          jsonb_build_object('delivery_fee', NEW.delivery_fee, 'margin_rate', 0.15),
          NOW()
        );
      END IF;

    ELSE
      -- CARD FLOW

      -- Restaurant receives order revenue
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
        'Comisión ' || public._fmt_pct(v_commission_rate) || ' - Pedido #' || NEW.id,
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
          jsonb_build_object('delivery_fee', NEW.delivery_fee, 'rate', 0.85),
          NOW()
        );
      END IF;

      -- Platform receives card payment (as payable)
      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        platform_payables_account_id, 'CASH_COLLECTED', -NEW.total_amount,
        'Dinero recibido por tarjeta - Pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object('payment_method', 'card', 'total_amount', NEW.total_amount),
        NOW()
      );

      -- Platform receives commission
      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        platform_revenue_account_id, 'PLATFORM_COMMISSION', platform_commission,
        'Comisión ' || public._fmt_pct(v_commission_rate) || ' - Pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );
    END IF;

    -- Recompute balances from transactions (authoritative)
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

-- 6) Create the trigger (ONLY one, clean state)
CREATE TRIGGER trigger_process_order_payment
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.process_order_payment_v2();

-- Done: Now only process_order_payment_v2 runs, using commission_bps from restaurants table
