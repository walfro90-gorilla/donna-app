-- ================================================================
-- Per-restaurant commission (15% default, up to 30%)
-- Idempotent patch: adds restaurants.commission_bps and updates RPCs/triggers
-- to compute PLATFORM_COMMISSION dynamically without breaking Balance Cero.
-- ================================================================

-- 1) Add commission_bps column to restaurants (basis points: 1500 = 15.00%)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'restaurants'
      AND column_name = 'commission_bps'
  ) THEN
    ALTER TABLE public.restaurants
      ADD COLUMN commission_bps integer NOT NULL DEFAULT 1500;
  END IF;
  -- Ensure a safe CHECK constraint (max 30%). Allow 0..3000 for future flexibility.
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

-- Helper: render percent label like '15%'
CREATE OR REPLACE FUNCTION public._fmt_pct(p_rate numeric)
RETURNS text AS $$
BEGIN
  RETURN trim(trailing '.' FROM trim(trailing '0' FROM to_char(p_rate * 100, 'FM999999990.99'))) || '%';
END; $$ LANGUAGE plpgsql IMMUTABLE;

-- 2) Update process_order_payment_v2() to use restaurant commission_bps
-- NOTE: Keep SECURITY DEFINER and search_path so it bypasses RLS safely.
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

    subtotal numeric;
    platform_commission numeric;
    delivery_earning numeric;
    platform_delivery_earning numeric;

    v_commission_bps integer;
    v_commission_rate numeric; -- 0.15 .. 0.30
BEGIN
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        -- Accounts
        SELECT a.id INTO restaurant_account_id
        FROM accounts a
        JOIN restaurants r ON r.user_id = a.user_id  
        WHERE r.id = NEW.restaurant_id
        LIMIT 1;

        SELECT a.id INTO delivery_agent_account_id
        FROM accounts a
        WHERE a.user_id = NEW.delivery_agent_id
        LIMIT 1;

        SELECT a.id INTO platform_revenue_account_id
        FROM accounts a
        WHERE a.user_id = '00000000-0000-0000-0000-000000000001'::uuid
        LIMIT 1;

        SELECT a.id INTO platform_payables_account_id
        FROM accounts a
        WHERE a.user_id = '00000000-0000-0000-0000-000000000002'::uuid
        LIMIT 1;

        IF restaurant_account_id IS NULL OR delivery_agent_account_id IS NULL OR 
           platform_revenue_account_id IS NULL OR platform_payables_account_id IS NULL THEN
            RAISE EXCEPTION 'Cuentas requeridas faltantes para process_order_payment_v2';
        END IF;

        -- Financials
        subtotal := NEW.total_amount - COALESCE(NEW.delivery_fee, 0);

        -- Commission rate per restaurant (bps -> rate). Default 1500 (15%)
        SELECT COALESCE(commission_bps, 1500) INTO v_commission_bps
        FROM public.restaurants WHERE id = NEW.restaurant_id;
        v_commission_rate := (COALESCE(v_commission_bps, 1500))::numeric / 10000.0;

        platform_commission := ROUND(subtotal * v_commission_rate, 2);

        -- Delivery split remains unchanged (85% / 15%)
        delivery_earning := ROUND(COALESCE(NEW.delivery_fee, 0) * 0.85, 2);
        platform_delivery_earning := COALESCE(NEW.delivery_fee, 0) - delivery_earning;

        -- Insert transactions (cash vs card flow unchanged)
        IF NEW.payment_method = 'cash' THEN
            INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
            VALUES (restaurant_account_id, 'ORDER_REVENUE', subtotal, 
                    'Ingreso por pedido #' || NEW.id, NEW.id, jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal), NOW());

            INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
            VALUES (restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission, 
                    format('Comisión %s - Pedido #%%s', public._fmt_pct(v_commission_rate))::text || NEW.id::text, NEW.id,
                    jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal), NOW());

            INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
            VALUES (delivery_agent_account_id, 'DELIVERY_EARNING', delivery_earning, 
                    'Ganancia delivery - Pedido #' || NEW.id, NEW.id, jsonb_build_object('delivery_fee', NEW.delivery_fee), NOW());

            INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
            VALUES (delivery_agent_account_id, 'CASH_COLLECTED', -NEW.total_amount, 
                    'Efectivo recolectado - Pedido #' || NEW.id, NEW.id, NOW());

            INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
            VALUES (platform_revenue_account_id, 'PLATFORM_COMMISSION', platform_commission, 
                    format('Comisión %s - Pedido #%%s', public._fmt_pct(v_commission_rate))::text || NEW.id::text, NEW.id,
                    jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal), NOW());

            INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
            VALUES (platform_revenue_account_id, 'DELIVERY_EARNING', platform_delivery_earning, 
                    'Margen delivery 15% - Pedido #' || NEW.id, NEW.id, jsonb_build_object('delivery_fee', NEW.delivery_fee), NOW());
        ELSE
            INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
            VALUES (restaurant_account_id, 'ORDER_REVENUE', subtotal, 
                    'Ingreso por pedido #' || NEW.id, NEW.id, jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal), NOW());

            INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
            VALUES (restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission, 
                    format('Comisión %s - Pedido #%%s', public._fmt_pct(v_commission_rate))::text || NEW.id::text, NEW.id,
                    jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal), NOW());

            INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
            VALUES (delivery_agent_account_id, 'DELIVERY_EARNING', delivery_earning, 
                    'Ganancia delivery - Pedido #' || NEW.id, NEW.id, jsonb_build_object('delivery_fee', NEW.delivery_fee), NOW());

            INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
            VALUES (platform_revenue_account_id, 'PLATFORM_COMMISSION', platform_commission, 
                    format('Comisión %s - Pedido #%%s', public._fmt_pct(v_commission_rate))::text || NEW.id::text, NEW.id,
                    jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal), NOW());

            INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
            VALUES (platform_payables_account_id, 'CASH_COLLECTED', -NEW.total_amount, 
                    'Dinero recibido por tarjeta - Pedido #' || NEW.id, NEW.id, NOW());
        END IF;

        -- Recompute balances via sum of transactions
        UPDATE accounts SET balance = (
            SELECT COALESCE(SUM(amount), 0) FROM account_transactions WHERE account_id = restaurant_account_id
        ) WHERE id = restaurant_account_id;

        UPDATE accounts SET balance = (
            SELECT COALESCE(SUM(amount), 0) FROM account_transactions WHERE account_id = delivery_agent_account_id
        ) WHERE id = delivery_agent_account_id;

        UPDATE accounts SET balance = (
            SELECT COALESCE(SUM(amount), 0) FROM account_transactions WHERE account_id = platform_revenue_account_id
        ) WHERE id = platform_revenue_account_id;

        UPDATE accounts SET balance = (
            SELECT COALESCE(SUM(amount), 0) FROM account_transactions WHERE account_id = platform_payables_account_id
        ) WHERE id = platform_payables_account_id;
    END IF;

    RETURN NEW;
END;
$$;

-- Ensure trigger exists (do not drop/recreate if already fine)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trigger_process_order_payment'
  ) THEN
    CREATE TRIGGER trigger_process_order_payment
      AFTER UPDATE ON public.orders
      FOR EACH ROW
      EXECUTE FUNCTION public.process_order_payment_v2();
  END IF;
END $$;

-- 3) Update older function process_order_financial_completion() with dynamic rate (in case it's used)
CREATE OR REPLACE FUNCTION public.process_order_financial_completion(order_uuid UUID)
RETURNS JSON AS $$
DECLARE
    v_order RECORD;
    v_restaurant_account_id UUID;
    v_delivery_account_id UUID;
    v_platform_revenue_account_id UUID;
    v_subtotal DECIMAL(10,2);
    v_commission DECIMAL(10,2);
    v_restaurant_earning DECIMAL(10,2);
    v_delivery_earning DECIMAL(10,2);
    v_result JSON;
    v_commission_bps integer;
    v_commission_rate numeric;
BEGIN
    SELECT o.*, r.name as restaurant_name, u.name as delivery_agent_name, COALESCE(r.commission_bps, 1500) as c_bps
    INTO v_order
    FROM public.orders o
    LEFT JOIN public.restaurants r ON o.restaurant_id = r.id
    LEFT JOIN public.users u ON o.delivery_agent_id = u.id
    WHERE o.id = order_uuid;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Order not found');
    END IF;
    IF v_order.status != 'delivered' THEN
        RETURN json_build_object('success', false, 'error', 'Order is not delivered yet');
    END IF;
    IF EXISTS (SELECT 1 FROM public.account_transactions WHERE order_id = order_uuid) THEN
        RETURN json_build_object('success', false, 'error', 'Transactions already processed for this order');
    END IF;

    SELECT id INTO v_restaurant_account_id
    FROM public.accounts 
    WHERE user_id = (SELECT user_id FROM public.restaurants WHERE id = v_order.restaurant_id)
      AND account_type ILIKE 'restaur%'
    LIMIT 1;

    SELECT id INTO v_delivery_account_id
    FROM public.accounts 
    WHERE user_id = v_order.delivery_agent_id
      AND account_type ILIKE 'delivery%'
    LIMIT 1;

    SELECT id INTO v_platform_revenue_account_id
    FROM public.accounts 
    WHERE user_id = (SELECT id FROM public.users WHERE email ILIKE 'platform+revenue%@%')
      OR account_type = 'platform_revenue'
    LIMIT 1;

    IF v_restaurant_account_id IS NULL OR v_delivery_account_id IS NULL OR v_platform_revenue_account_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Required accounts not found');
    END IF;

    v_subtotal := v_order.total_amount - COALESCE(v_order.delivery_fee, 0);
    v_commission_bps := COALESCE(v_order.c_bps, 1500);
    v_commission_rate := v_commission_bps::numeric / 10000.0;
    v_commission := ROUND(v_subtotal * v_commission_rate, 2);
    v_restaurant_earning := v_subtotal - v_commission;
    v_delivery_earning := COALESCE(v_order.delivery_fee, 0);

    INSERT INTO public.account_transactions (account_id, type, amount, order_id, description, metadata)
    VALUES (
        v_restaurant_account_id,
        'ORDER_REVENUE',
        v_restaurant_earning,
        order_uuid,
        format('Ingreso por orden #%s - %s', LEFT(order_uuid::text, 8), v_order.restaurant_name),
        json_build_object('order_id', order_uuid, 'subtotal', v_subtotal, 'commission_rate', v_commission_rate, 'commission_bps', v_commission_bps)
    );

    IF v_delivery_earning > 0 THEN
        INSERT INTO public.account_transactions (account_id, type, amount, order_id, description, metadata)
        VALUES (
            v_delivery_account_id,
            'DELIVERY_EARNING',
            v_delivery_earning,
            order_uuid,
            format('Delivery fee - Orden #%s', LEFT(order_uuid::text, 8)),
            json_build_object('order_id', order_uuid, 'delivery_fee', v_delivery_earning)
        );
    END IF;

    INSERT INTO public.account_transactions (account_id, type, amount, order_id, description, metadata)
    VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_COMMISSION',
        v_commission,
        order_uuid,
        format('Comisión %s - Orden #%s', public._fmt_pct(v_commission_rate), LEFT(order_uuid::text, 8)),
        json_build_object('order_id', order_uuid, 'subtotal', v_subtotal, 'commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'restaurant_name', v_order.restaurant_name)
    );

    UPDATE public.accounts 
    SET balance = balance + v_restaurant_earning, updated_at = NOW()
    WHERE id = v_restaurant_account_id;

    IF v_delivery_earning > 0 THEN
        UPDATE public.accounts 
        SET balance = balance + v_delivery_earning, updated_at = NOW()
        WHERE id = v_delivery_account_id;
    END IF;

    UPDATE public.accounts 
    SET balance = balance + v_commission, updated_at = NOW()
    WHERE id = v_platform_revenue_account_id;

    v_result := json_build_object(
        'success', true,
        'order_id', order_uuid,
        'calculations', json_build_object(
            'total_amount', v_order.total_amount,
            'subtotal', v_subtotal,
            'delivery_fee', v_delivery_earning,
            'commission', v_commission,
            'commission_rate', v_commission_rate,
            'restaurant_earning', v_restaurant_earning,
            'delivery_earning', v_delivery_earning
        )
    );

    RETURN v_result;
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'error', SQLERRM, 'error_code', SQLSTATE);
END;
$$ LANGUAGE plpgsql;

-- 4) Update rpc_post_client_default to use dynamic restaurant commission
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
  v_actor uuid := auth.uid();
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

  IF EXISTS (
    SELECT 1 FROM public.account_transactions 
    WHERE order_id = p_order_id AND (metadata ->> 'reason') = 'client_default'
  ) THEN
    RETURN jsonb_build_object('success', true, 'skipped', true, 'message', 'Asientos ya creados previamente');
  END IF;

  SELECT a.id INTO v_restaurant_account
  FROM public.accounts a JOIN public.restaurants r ON r.user_id = a.user_id
  WHERE r.id = v_order.restaurant_id LIMIT 1;

  SELECT a.id INTO v_delivery_account FROM public.accounts a WHERE a.user_id = v_order.delivery_agent_id LIMIT 1;

  PERFORM public.ensure_client_profile_and_account(v_order.user_id);
  SELECT id INTO v_client_account FROM public.accounts WHERE user_id = v_order.user_id AND account_type = 'client' LIMIT 1;

  SELECT id INTO v_platform_revenue FROM public.accounts WHERE account_type = 'platform_revenue' LIMIT 1;
  IF v_platform_revenue IS NULL THEN
    SELECT id INTO v_platform_revenue FROM public.accounts
    WHERE user_id = '00000000-0000-0000-0000-000000000001'::uuid LIMIT 1;
  END IF;

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
    format('Ingreso neto por falla de cliente - Orden #%s', LEFT(p_order_id::text, 8)),
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

-- End of patch
