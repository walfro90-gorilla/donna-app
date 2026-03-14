-- ============================================================================
-- FIX: create_order_safe usaba columna 'updated_by' (no existe)
--      debe ser 'updated_by_user_id' según DATABASE_SCHEMA
-- Ejecutar en Supabase Dashboard → SQL Editor
-- ============================================================================

DROP FUNCTION IF EXISTS public.create_order_safe(
  uuid, uuid, double precision, double precision, text, text,
  double precision, double precision, text, double precision
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
  p_cash_amount      double precision DEFAULT NULL
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

  -- Insert initial status update (FIX: updated_by_user_id, not updated_by; id is bigint autoincrement)
  INSERT INTO public.order_status_updates (
    order_id, status, updated_by_user_id, created_at
  ) VALUES (
    v_order_id, 'pending', p_user_id, now()
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
