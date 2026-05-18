-- =============================================================================
-- BILLING DUAL MODEL - 04 ORDER RPCS
--   1) create_order_safe: snapshot de billing_mode al crear; acepta tip_amount;
--      valida suscripción activa del restaurante si modo=subscription.
--   2) accept_order: rechaza repartidores con suscripción 'suspended'.
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1) create_order_safe (firma extendida + sin romper la actual)
--    Nueva firma agrega p_tip_amount como último opcional.
--    Snapshot leído de platform_settings.billing_mode al INSERT.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_order_safe(
  p_user_id          uuid,
  p_restaurant_id    uuid,
  p_total_amount     double precision,
  p_delivery_fee     double precision DEFAULT 0.0,
  p_payment_method   text             DEFAULT 'cash',
  p_delivery_address text             DEFAULT NULL,
  p_delivery_lat     double precision DEFAULT NULL,
  p_delivery_lon     double precision DEFAULT NULL,
  p_order_notes      text             DEFAULT NULL,
  p_cash_amount      double precision DEFAULT NULL,
  p_tip_amount       double precision DEFAULT 0.0
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id     uuid;
  v_pickup_code  text;
  v_billing_mode text;
  v_restaurant_user_id uuid;
  v_restaurant_sub_status text;
BEGIN
  -- Modo vigente al momento del INSERT (snapshot por orden)
  SELECT value INTO v_billing_mode FROM public.platform_settings WHERE key = 'billing_mode';
  v_billing_mode := COALESCE(v_billing_mode, 'commission');

  -- Si modo=subscription, validar que el restaurante tenga su cuota al día
  IF v_billing_mode = 'subscription' THEN
    SELECT r.user_id INTO v_restaurant_user_id
    FROM public.restaurants r WHERE r.id = p_restaurant_id;

    -- FIX 2026-05-18: buscar subscription via user_id, no via account_id
    -- (robusto a cuentas duplicadas del mismo usuario)
    SELECT s.status INTO v_restaurant_sub_status
    FROM public.subscriptions s
    JOIN public.accounts a ON a.id = s.account_id
    WHERE a.user_id = v_restaurant_user_id
      AND s.role = 'restaurant'
    ORDER BY s.created_at DESC LIMIT 1;

    IF v_restaurant_sub_status = 'suspended' THEN
      RETURN json_build_object(
        'success', false,
        'error', 'Restaurant subscription is suspended',
        'code', 'restaurant_suspended'
      );
    END IF;
  END IF;

  v_pickup_code := LPAD(floor(random() * 10000)::text, 4, '0');

  INSERT INTO public.orders (
    id, user_id, restaurant_id, status, total_amount, delivery_fee,
    payment_method, delivery_address, delivery_lat, delivery_lon,
    pickup_code, order_notes, cash_amount,
    billing_mode, tip_amount,
    created_at, updated_at
  ) VALUES (
    gen_random_uuid(), p_user_id, p_restaurant_id, 'pending', p_total_amount, p_delivery_fee,
    p_payment_method, p_delivery_address, p_delivery_lat, p_delivery_lon,
    v_pickup_code, p_order_notes, p_cash_amount,
    v_billing_mode, COALESCE(p_tip_amount, 0),
    now(), now()
  ) RETURNING id INTO v_order_id;

  INSERT INTO public.order_status_updates (
    order_id, status, updated_by_user_id, created_at
  ) VALUES (
    v_order_id, 'pending', p_user_id, now()
  );

  RETURN json_build_object(
    'success',      true,
    'order_id',     v_order_id,
    'pickup_code',  v_pickup_code,
    'billing_mode', v_billing_mode,
    'tip_amount',   COALESCE(p_tip_amount, 0)
  );

EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_order_safe(
  uuid, uuid, double precision, double precision, text, text,
  double precision, double precision, text, double precision, double precision
) TO authenticated;

-- =============================================================================
-- 2) accept_order: validar que la suscripción del repartidor no esté 'suspended'
--    Solo se bloquea cuando el modo global = 'subscription'.
--    Una vez asignada la orden, las RPCs de update_status NO se tocan
--    (las órdenes en vuelo deben completarse aunque la cuenta caiga en suspended).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.accept_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      uuid := auth.uid();
  v_billing_mode text;
  v_sub_status   text;
  v_updated      boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Not authenticated');
  END IF;

  SELECT value INTO v_billing_mode FROM public.platform_settings WHERE key = 'billing_mode';
  v_billing_mode := COALESCE(v_billing_mode, 'commission');

  IF v_billing_mode = 'subscription' THEN
    -- FIX 2026-05-18: buscar subscription via user_id (robusto a cuentas duplicadas)
    SELECT s.status INTO v_sub_status
    FROM public.subscriptions s
    JOIN public.accounts a ON a.id = s.account_id
    WHERE a.user_id = v_user_id
      AND s.role = 'delivery_agent'
    ORDER BY s.created_at DESC LIMIT 1;

    IF v_sub_status = 'suspended' THEN
      RETURN jsonb_build_object(
        'success', false,
        'message', 'Delivery subscription is suspended',
        'code', 'delivery_suspended'
      );
    END IF;
  END IF;

  UPDATE public.orders o
  SET delivery_agent_id = v_user_id,
      assigned_at = NOW(),
      status = 'assigned',
      updated_at = NOW()
  WHERE o.id = p_order_id
    AND o.delivery_agent_id IS NULL
    AND o.status IN ('confirmed', 'in_preparation', 'ready_for_pickup')
  RETURNING TRUE INTO v_updated;

  IF NOT v_updated THEN
    RETURN jsonb_build_object('success', false, 'message', 'Order not available');
  END IF;

  BEGIN
    INSERT INTO public.order_status_updates (order_id, status, actor_role, actor_id, updated_by_user_id, created_at)
    VALUES (p_order_id, 'assigned', 'repartidor', v_user_id, v_user_id, NOW());
  EXCEPTION WHEN others THEN
    NULL;
  END;

  RETURN jsonb_build_object('success', true, 'message', 'Order assigned');
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_order(uuid) TO authenticated;

COMMIT;
