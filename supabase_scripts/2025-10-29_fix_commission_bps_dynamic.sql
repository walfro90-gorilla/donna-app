-- ================================================================
-- Dynamic commission by restaurant (commission_bps) + trigger cleanup
-- - Replaces any hardcoded 20% with restaurants.commission_bps
-- - Keeps Balance Cero intact for both cash and card flows
-- - Uses existing platform accounts by account_type (no UUID hardcodes)
-- - Adds clear metadata and labels with the rate used
-- - Removes legacy trigger process_payment_on_delivery if present
-- ================================================================

-- 0) Ensure restaurants.commission_bps exists with safe bounds (15% default)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'restaurants' AND column_name = 'commission_bps'
  ) THEN
    ALTER TABLE public.restaurants ADD COLUMN commission_bps integer NOT NULL DEFAULT 1500;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname = 'public' AND t.relname = 'restaurants' AND c.conname = 'restaurants_commission_bps_check'
  ) THEN
    ALTER TABLE public.restaurants
      ADD CONSTRAINT restaurants_commission_bps_check
      CHECK (commission_bps >= 0 AND commission_bps <= 3000);
  END IF;
END $$;

-- Helper to format rate as text like '15%'
CREATE OR REPLACE FUNCTION public._fmt_pct(p_rate numeric)
RETURNS text AS $$
BEGIN
  RETURN trim(trailing '.' FROM trim(trailing '0' FROM to_char(p_rate * 100, 'FM999999990.99'))) || '%';
END; $$ LANGUAGE plpgsql IMMUTABLE;

-- 1) Replace process_order_payment_v2 to use commission_bps
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
  platform_delivery_earning numeric;

  v_commission_bps integer;
  v_commission_rate numeric; -- 0.00 .. 0.30
  v_any_txn boolean;
BEGIN
  -- Only act on transition to delivered
  IF NEW.status = 'delivered' AND OLD.status <> 'delivered' THEN

    -- Idempotency guard: if we've already posted any ORDER_REVENUE or PLATFORM_COMMISSION for this order, skip
    SELECT EXISTS (
      SELECT 1 FROM public.account_transactions
      WHERE order_id = NEW.id AND type IN ('ORDER_REVENUE','PLATFORM_COMMISSION')
    ) INTO v_any_txn;
    IF v_any_txn THEN
      RETURN NEW;
    END IF;

    -- Resolve restaurant account via restaurants.user_id
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

    -- Resolve delivery account (optional)
    IF NEW.delivery_agent_id IS NOT NULL THEN
      SELECT a.id INTO delivery_agent_account_id
      FROM public.accounts a
      WHERE a.user_id = NEW.delivery_agent_id AND a.account_type = 'delivery_agent'
      ORDER BY a.created_at ASC
      LIMIT 1;
    END IF;

    -- Resolve platform revenue account (existing account by type)
    SELECT a.id INTO platform_revenue_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_revenue'
    ORDER BY a.created_at ASC
    LIMIT 1;

    -- Resolve platform payables account (existing account by type)
    SELECT a.id INTO platform_payables_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_payables'
    ORDER BY a.created_at ASC
    LIMIT 1;

    -- Required accounts guard
    IF restaurant_account_id IS NULL OR platform_revenue_account_id IS NULL OR platform_payables_account_id IS NULL
       OR (NEW.delivery_agent_id IS NOT NULL AND delivery_agent_account_id IS NULL) THEN
      RAISE EXCEPTION 'Cuentas requeridas faltantes (rest:% del:% plat_rev:% plat_pay:%). Crea/resuelve manualmente y reintenta.',
        restaurant_account_id, delivery_agent_account_id, platform_revenue_account_id, platform_payables_account_id;
    END IF;

    -- Financials
    subtotal := NEW.total_amount - COALESCE(NEW.delivery_fee, 0);

    -- Commission rate from restaurants (bps -> rate). Default 1500 (15%)
    SELECT COALESCE(commission_bps, 1500) INTO v_commission_bps
    FROM public.restaurants WHERE id = NEW.restaurant_id;
    v_commission_rate := (COALESCE(v_commission_bps, 1500))::numeric / 10000.0;

    platform_commission := ROUND(subtotal * v_commission_rate, 2);
    delivery_earning := ROUND(COALESCE(NEW.delivery_fee, 0) * 0.85, 2);
    platform_delivery_earning := COALESCE(NEW.delivery_fee, 0) - delivery_earning;

    -- Insert transactions (cash vs card)
    IF NEW.payment_method = 'cash' THEN
      -- Restaurant revenue
      INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        restaurant_account_id, 'ORDER_REVENUE', subtotal,
        'Ingreso por pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );

      -- Restaurant pays platform commission
      INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission,
        format('Comisión %s - Pedido #%%s', public._fmt_pct(v_commission_rate))::text || NEW.id::text,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );

      -- Delivery earning (if delivery account exists)
      IF delivery_agent_account_id IS NOT NULL THEN
        INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
        VALUES (
          delivery_agent_account_id, 'DELIVERY_EARNING', delivery_earning,
          'Ganancia delivery - Pedido #' || NEW.id,
          NEW.id,
          jsonb_build_object('delivery_fee', NEW.delivery_fee),
          NOW()
        );

        -- Cash collected negative liability for delivery agent
        INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
        VALUES (
          delivery_agent_account_id, 'CASH_COLLECTED', -NEW.total_amount,
          'Efectivo recolectado - Pedido #' || NEW.id,
          NEW.id,
          NOW()
        );
      END IF;

      -- Platform commission and delivery margin
      INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        platform_revenue_account_id, 'PLATFORM_COMMISSION', platform_commission,
        format('Comisión %s - Pedido #%%s', public._fmt_pct(v_commission_rate))::text || NEW.id::text,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );

      INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        platform_revenue_account_id, 'DELIVERY_EARNING', platform_delivery_earning,
        'Margen delivery 15% - Pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object('delivery_fee', NEW.delivery_fee),
        NOW()
      );
    ELSE
      -- Card flow
      INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        restaurant_account_id, 'ORDER_REVENUE', subtotal,
        'Ingreso por pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );

      INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission,
        format('Comisión %s - Pedido #%%s', public._fmt_pct(v_commission_rate))::text || NEW.id::text,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );

      IF delivery_agent_account_id IS NOT NULL THEN
        INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
        VALUES (
          delivery_agent_account_id, 'DELIVERY_EARNING', delivery_earning,
          'Ganancia delivery - Pedido #' || NEW.id,
          NEW.id,
          jsonb_build_object('delivery_fee', NEW.delivery_fee),
          NOW()
        );
      END IF;

      -- Platform receives net card amount as payable (negative)
      INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
      VALUES (
        platform_payables_account_id, 'CASH_COLLECTED', -NEW.total_amount,
        'Dinero recibido por tarjeta - Pedido #' || NEW.id,
        NEW.id,
        NOW()
      );

      INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        platform_revenue_account_id, 'PLATFORM_COMMISSION', platform_commission,
        format('Comisión %s - Pedido #%%s', public._fmt_pct(v_commission_rate))::text || NEW.id::text,
        NEW.id,
        jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal),
        NOW()
      );
    END IF;

    -- Recompute balances via sum of transactions
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

-- Ensure v2 trigger and remove legacy one
DO $$
BEGIN
  -- Drop legacy trigger if exists
  IF EXISTS (
    SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trigger_process_payment_on_delivery'
  ) THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trigger_process_payment_on_delivery ON public.orders';
  END IF;

  -- Ensure v2 trigger exists and points to process_order_payment_v2
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trigger_process_order_payment'
  ) THEN
    CREATE TRIGGER trigger_process_order_payment
      AFTER UPDATE ON public.orders
      FOR EACH ROW
      EXECUTE FUNCTION public.process_order_payment_v2();
  END IF;
END $$;

-- 2) Replace rpc_post_client_default to use commission_bps dynamically
CREATE OR REPLACE FUNCTION public.rpc_post_client_default(
  p_order_id uuid,
  p_reason text DEFAULT 'Falla de Cliente'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_restaurant_account uuid;
  v_delivery_account uuid;
  v_client_account uuid;
  v_platform_revenue uuid;
  v_subtotal numeric;
  v_commission numeric;
  v_restaurant_net numeric;
  v_delivery_earning numeric;
  v_platform_delivery_margin numeric;
  v_now timestamptz := now();
  v_status_changed boolean := false;
  v_commission_bps integer;
  v_commission_rate numeric;
BEGIN
  SELECT o.*, COALESCE(r.commission_bps, 1500) AS c_bps
  INTO v_order
  FROM public.orders o
  LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.id = p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Orden % no existe', p_order_id; END IF;

  -- Idempotency: skip if already posted client_default for this order
  IF EXISTS (
    SELECT 1 FROM public.account_transactions 
    WHERE order_id = p_order_id AND (metadata ->> 'reason') = 'client_default'
  ) THEN
    RETURN jsonb_build_object('success', true, 'skipped', true, 'message', 'Asientos ya creados previamente');
  END IF;

  -- Resolve accounts
  SELECT a.id INTO v_restaurant_account
  FROM public.accounts a JOIN public.restaurants r ON r.user_id = a.user_id
  WHERE r.id = v_order.restaurant_id AND a.account_type = 'restaurant'
  ORDER BY a.created_at ASC LIMIT 1;

  SELECT a.id INTO v_delivery_account FROM public.accounts a 
  WHERE a.user_id = v_order.delivery_agent_id AND a.account_type = 'delivery_agent'
  ORDER BY a.created_at ASC LIMIT 1;

  PERFORM public.ensure_client_profile_and_account(v_order.user_id);
  SELECT id INTO v_client_account FROM public.accounts WHERE user_id = v_order.user_id AND account_type = 'client' LIMIT 1;

  SELECT id INTO v_platform_revenue FROM public.accounts WHERE account_type = 'platform_revenue' ORDER BY created_at ASC LIMIT 1;

  IF v_restaurant_account IS NULL OR v_delivery_account IS NULL OR v_client_account IS NULL OR v_platform_revenue IS NULL THEN
    RAISE EXCEPTION 'No se pudieron resolver cuentas necesarias (restaurante/repartidor/cliente/plataforma)';
  END IF;

  v_subtotal := COALESCE(v_order.total_amount, 0) - COALESCE(v_order.delivery_fee, 0);
  v_commission_bps := COALESCE(v_order.c_bps, 1500);
  v_commission_rate := v_commission_bps::numeric / 10000.0;
  v_commission := ROUND(v_subtotal * v_commission_rate, 2);
  v_restaurant_net := v_subtotal - v_commission;
  v_delivery_earning := ROUND(COALESCE(v_order.delivery_fee, 0) * 0.85, 2);
  v_platform_delivery_margin := COALESCE(v_order.delivery_fee, 0) - v_delivery_earning;

  INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)
  VALUES (
    v_restaurant_account,
    'ORDER_REVENUE',
    v_restaurant_net,
    p_order_id,
    format('Ingreso neto (comisión %s) - Orden #%%s', public._fmt_pct(v_commission_rate))::text || LEFT(p_order_id::text, 8),
    jsonb_build_object('reason','client_default','subtotal', v_subtotal, 'commission', v_commission, 'commission_rate', v_commission_rate, 'commission_bps', v_commission_bps),
    v_now
  );

  IF v_delivery_earning > 0 THEN
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)
    VALUES (
      v_delivery_account,
      'DELIVERY_EARNING',
      v_delivery_earning,
      p_order_id,
      format('Ganancia delivery por falla de cliente - Orden #%s', LEFT(p_order_id::text, 8)),
      jsonb_build_object('reason','client_default','delivery_fee', v_order.delivery_fee),
      v_now
    );
  END IF;

  INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)
  VALUES (
    v_client_account,
    'CLIENT_DEBT',
    -COALESCE(v_order.total_amount, 0),
    p_order_id,
    format('Deuda por falla de cliente - Orden #%s', LEFT(p_order_id::text, 8)),
    jsonb_build_object('reason','client_default'),
    v_now
  );

  IF v_commission > 0 THEN
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)
    VALUES (
      v_platform_revenue,
      'PLATFORM_COMMISSION',
      v_commission,
      p_order_id,
      format('Comisión %s - Orden #%s', public._fmt_pct(v_commission_rate), LEFT(p_order_id::text, 8)),
      jsonb_build_object('reason','client_default','subtotal', v_subtotal, 'commission_rate', v_commission_rate, 'commission_bps', v_commission_bps),
      v_now
    );
  END IF;

  IF v_platform_delivery_margin > 0 THEN
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)
    VALUES (
      v_platform_revenue,
      'PLATFORM_DELIVERY_MARGIN',
      v_platform_delivery_margin,
      p_order_id,
      format('Margen delivery - Orden #%s', LEFT(p_order_id::text, 8)),
      jsonb_build_object('reason','client_default','delivery_fee', v_order.delivery_fee),
      v_now
    );
  END IF;

  PERFORM public.rpc_recompute_account_balance(v_restaurant_account);
  PERFORM public.rpc_recompute_account_balance(v_delivery_account);
  PERFORM public.rpc_recompute_account_balance(v_client_account);
  PERFORM public.rpc_recompute_account_balance(v_platform_revenue);

  IF v_order.status <> 'canceled' THEN
    UPDATE public.orders SET status = 'canceled', updated_at = v_now WHERE id = p_order_id;
    v_status_changed := true;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'posted', 5,
    'order_status_marked_canceled', v_status_changed,
    'amounts', jsonb_build_object(
      'subtotal', v_subtotal,
      'commission', v_commission,
      'commission_rate', v_commission_rate,
      'commission_bps', v_commission_bps,
      'restaurant_net', v_restaurant_net,
      'delivery_earning', v_delivery_earning,
      'platform_delivery_margin', v_platform_delivery_margin,
      'client_debt', COALESCE(v_order.total_amount,0)
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_post_client_default(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.rpc_post_client_default(uuid, text) TO authenticated, service_role;

-- 3) Optional: helper to compute dynamic split for a given order (for diagnostics/UI)
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

-- End of patch
