-- ============================================================================
-- ADD: cash_amount a orders + actualizar create_order_safe
-- Date: 2026-03-14
-- ============================================================================
-- cash_amount = monto con el que el cliente pagará en efectivo
-- NULL  → pago con tarjeta/SPEI o el campo no fue capturado
-- = total_amount → pago exacto, sin cambio
-- > total_amount → necesita cambio (cash_amount - total_amount)
-- ============================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS cash_amount numeric DEFAULT NULL;

COMMENT ON COLUMN public.orders.cash_amount IS
  'Monto en efectivo con el que pagará el cliente. NULL=no aplica (tarjeta/SPEI). = total_amount → exacto. > total_amount → dar cambio.';

-- ============================================================================
-- Actualizar create_order_safe para aceptar p_cash_amount (opcional)
-- ============================================================================

DROP FUNCTION IF EXISTS public.create_order_safe(
  uuid, uuid, double precision, double precision, text, text, double precision, double precision, text
);

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
  p_cash_amount      double precision DEFAULT NULL   -- NUEVO: monto con el que paga el cliente
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id   uuid;
  v_pickup_code text;
BEGIN
  -- Generate 4-digit pickup code
  v_pickup_code := LPAD(floor(random() * 10000)::text, 4, '0');

  INSERT INTO public.orders (
    id, user_id, restaurant_id, status, total_amount, delivery_fee,
    payment_method, delivery_address, delivery_lat, delivery_lon,
    pickup_code, order_notes, cash_amount, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), p_user_id, p_restaurant_id, 'pending', p_total_amount, p_delivery_fee,
    p_payment_method, p_delivery_address, p_delivery_lat, p_delivery_lon,
    v_pickup_code, p_order_notes, p_cash_amount, now(), now()
  ) RETURNING id INTO v_order_id;

  -- Insert initial status update
  INSERT INTO public.order_status_updates (
    id, order_id, status, updated_by, created_at
  ) VALUES (
    gen_random_uuid(), v_order_id, 'pending', p_user_id, now()
  );

  RETURN json_build_object(
    'success',      true,
    'order_id',     v_order_id,
    'pickup_code',  v_pickup_code
  );

EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_order_safe(
  uuid, uuid, double precision, double precision, text, text,
  double precision, double precision, text, double precision
) TO authenticated;

-- ============================================================================
-- Verificación
-- ============================================================================
-- SELECT column_name, data_type FROM information_schema.columns
-- WHERE table_name = 'orders' AND column_name = 'cash_amount';
-- → debe devolver: cash_amount | numeric
--
-- SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'create_order_safe';
-- → debe incluir p_cash_amount
