-- ================================================================
-- Use only existing accounts for process_order_payment_v2
-- - No auto-creation of users nor accounts
-- - Resolve platform accounts by existing platform users' emails
-- - Keep Balance Cero logic and dynamic restaurant commission_bps
-- - Idempotent: just CREATE OR REPLACE FUNCTION
-- ================================================================

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
  v_commission_rate numeric; -- 0.15 .. 0.30
BEGIN
  -- Only act when transitioning to delivered
  IF NEW.status = 'delivered' AND OLD.status <> 'delivered' THEN

    -- Resolve restaurant user_id and account
    SELECT r.user_id INTO v_restaurant_user_id
    FROM public.restaurants r
    WHERE r.id = NEW.restaurant_id;

    IF v_restaurant_user_id IS NULL THEN
      RAISE EXCEPTION 'Restaurant % has no user_id linked', NEW.restaurant_id;
    END IF;

    SELECT a.id INTO restaurant_account_id
    FROM public.accounts a
    WHERE a.user_id = v_restaurant_user_id AND a.account_type = 'restaurant'
    LIMIT 1;

    -- Resolve delivery account (if applicable)
    IF NEW.delivery_agent_id IS NOT NULL THEN
      SELECT a.id INTO delivery_agent_account_id
      FROM public.accounts a
      WHERE a.user_id = NEW.delivery_agent_id AND a.account_type = 'delivery_agent'
      LIMIT 1;
    END IF;

    -- Resolve platform accounts using existing platform users
    -- We distinguish them by email convention already present in your DB
    SELECT a.id INTO platform_revenue_account_id
    FROM public.accounts a
    JOIN public.users u ON u.id = a.user_id
    WHERE a.account_type = 'platform'
      AND u.email ILIKE 'platform+revenue@%'
    ORDER BY a.created_at ASC
    LIMIT 1;

    SELECT a.id INTO platform_payables_account_id
    FROM public.accounts a
    JOIN public.users u ON u.id = a.user_id
    WHERE a.account_type = 'platform'
      AND u.email ILIKE 'platform+payables@%'
    ORDER BY a.created_at ASC
    LIMIT 1;

    -- Final guard: all required accounts must already exist
    IF restaurant_account_id IS NULL OR platform_revenue_account_id IS NULL OR platform_payables_account_id IS NULL 
       OR (NEW.delivery_agent_id IS NOT NULL AND delivery_agent_account_id IS NULL) THEN
      RAISE EXCEPTION 'Cuentas requeridas faltantes (rest:% del:% plat_rev:% plat_pay:%). Crea manualmente las cuentas y reintenta.',
        restaurant_account_id, delivery_agent_account_id, platform_revenue_account_id, platform_payables_account_id;
    END IF;

    -- Financials
    subtotal := NEW.total_amount - COALESCE(NEW.delivery_fee, 0);

    -- Commission rate per restaurant (bps -> rate). Default 1500 (15%)
    SELECT COALESCE(commission_bps, 1500) INTO v_commission_bps
    FROM public.restaurants WHERE id = NEW.restaurant_id;
    v_commission_rate := (COALESCE(v_commission_bps, 1500))::numeric / 10000.0;

    platform_commission := ROUND(subtotal * v_commission_rate, 2);
    delivery_earning := ROUND(COALESCE(NEW.delivery_fee, 0) * 0.85, 2);
    platform_delivery_earning := COALESCE(NEW.delivery_fee, 0) - delivery_earning;

    -- Insert transactions (cash vs card flow unchanged)
    IF NEW.payment_method = 'cash' THEN
      INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (restaurant_account_id, 'ORDER_REVENUE', subtotal, 
              'Ingreso por pedido #' || NEW.id, NEW.id, jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal), NOW());

      INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission, 
              'Comisión plataforma - Pedido #' || NEW.id, NEW.id,
              jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal), NOW());

      INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (delivery_agent_account_id, 'DELIVERY_EARNING', delivery_earning, 
              'Ganancia delivery - Pedido #' || NEW.id, NEW.id, jsonb_build_object('delivery_fee', NEW.delivery_fee), NOW());

      INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
      VALUES (delivery_agent_account_id, 'CASH_COLLECTED', -NEW.total_amount, 
              'Efectivo recolectado - Pedido #' || NEW.id, NEW.id, NOW());

      INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (platform_revenue_account_id, 'PLATFORM_COMMISSION', platform_commission, 
              'Comisión plataforma - Pedido #' || NEW.id, NEW.id,
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
              'Comisión plataforma - Pedido #' || NEW.id, NEW.id,
              jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal), NOW());

      INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (delivery_agent_account_id, 'DELIVERY_EARNING', delivery_earning, 
              'Ganancia delivery - Pedido #' || NEW.id, NEW.id, jsonb_build_object('delivery_fee', NEW.delivery_fee), NOW());

      INSERT INTO account_transactions (account_id, type, amount, description, order_id, created_at)
      VALUES (platform_payables_account_id, 'CASH_COLLECTED', -NEW.total_amount, 
              'Dinero recibido por tarjeta - Pedido #' || NEW.id, NEW.id, NOW());

      INSERT INTO account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (platform_revenue_account_id, 'PLATFORM_COMMISSION', platform_commission, 
              'Comisión plataforma - Pedido #' || NEW.id, NEW.id,
              jsonb_build_object('commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'subtotal', subtotal), NOW());
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

-- Ensure trigger exists (create if missing)
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
