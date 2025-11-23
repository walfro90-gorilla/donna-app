-- =====================================================================
-- Finalize: dynamic commission_bps with enforced trigger (authoritative)
-- Why: Feed still shows 20% and NULL description/metadata. Ensure the
--      correct trigger/function is the only one firing in production.
-- Effects:
--  - Drops legacy triggers/functions that may override logic.
--  - Uses restaurants.commission_bps (bps) with default 1500, clamped 0..3000.
--  - Writes description and metadata on all account_transactions.
--  - Uses schema-approved types: ORDER_REVENUE, PLATFORM_COMMISSION,
--    DELIVERY_EARNING, PLATFORM_DELIVERY_MARGIN, CASH_COLLECTED.
--  - Keeps Balance Cero for cash and card flows.
--  - Idempotent: safe to re-run.
-- =====================================================================

-- 0) Ensure restaurants.commission_bps exists and bounded
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

-- 1) Drop any legacy triggers that might still be firing
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

-- 2) Drop/replace older functions to avoid conflicts
DROP FUNCTION IF EXISTS public.process_order_payment();
DROP FUNCTION IF EXISTS public.process_order_payment_on_delivery();

-- 3) Authoritative trigger function using commission_bps
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
  -- Only act on transition to delivered
  IF NEW.status = 'delivered' AND OLD.status <> 'delivered' THEN

    -- Idempotency: skip if already posted main entries for this order
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

    -- Platform accounts by account_type (per schema)
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
    SELECT GREATEST(0, LEAST(COALESCE(commission_bps, 1500), 3000)) INTO v_commission_bps
    FROM public.restaurants WHERE id = NEW.restaurant_id;
    v_commission_rate := v_commission_bps::numeric / 10000.0;

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

      -- Platform delivery margin (explicit type)
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

    -- Recompute balances via sum of transactions (authoritative)
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

-- 4) Create the trigger pointing to v2 (single source of truth)
CREATE TRIGGER trigger_process_order_payment
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.process_order_payment_v2();

-- End finalization
