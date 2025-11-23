-- RPCs for live location

-- Upsert driver latest location + append history (throttled) + mirror into users.lat/lon
CREATE OR REPLACE FUNCTION public.update_my_location(
  p_lat double precision,
  p_lng double precision,
  p_accuracy double precision DEFAULT NULL,
  p_speed double precision DEFAULT NULL,
  p_heading double precision DEFAULT NULL,
  p_order_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_order_id uuid;
  v_now timestamptz := now();
  v_prev_lat double precision;
  v_prev_lng double precision;
  v_prev_time timestamptz;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  -- Resolve order id (if not provided) to most recent active one
  IF p_order_id IS NOT NULL THEN
    v_order_id := p_order_id;
  ELSE
    SELECT o.id
      INTO v_order_id
    FROM public.orders o
    WHERE o.delivery_agent_id = v_user_id
      AND public._is_active_delivery_status(o.status)
    ORDER BY o.updated_at DESC NULLS LAST
    LIMIT 1;
  END IF;

  -- Upsert latest
  INSERT INTO public.courier_locations_latest AS l
    (user_id, order_id, lat, lon, accuracy, speed, heading, last_seen_at)
  VALUES
    (v_user_id, v_order_id, p_lat, p_lng, p_accuracy, p_speed, p_heading, v_now)
  ON CONFLICT (user_id) DO UPDATE
  SET order_id    = COALESCE(EXCLUDED.order_id, l.order_id),
      lat         = EXCLUDED.lat,
      lon         = EXCLUDED.lon,
      accuracy    = EXCLUDED.accuracy,
      speed       = EXCLUDED.speed,
      heading     = EXCLUDED.heading,
      last_seen_at= EXCLUDED.last_seen_at;

  -- Mirror into users for backward compatibility (client fallback path)
  UPDATE public.users u
  SET lat = p_lat,
      lon = p_lng,
      updated_at = v_now
  WHERE u.id = v_user_id;

  -- Throttled history insert: ≥ ~11m or ≥ 10s since last sample
  SELECT h.lat, h.lon, h.recorded_at
    INTO v_prev_lat, v_prev_lng, v_prev_time
  FROM public.courier_locations_history h
  WHERE h.user_id = v_user_id
  ORDER BY h.recorded_at DESC
  LIMIT 1;

  IF v_prev_time IS NULL
     OR abs(p_lat - v_prev_lat) > 0.0001
     OR abs(p_lng - v_prev_lng) > 0.0001
     OR v_now - v_prev_time > INTERVAL '10 seconds' THEN
    INSERT INTO public.courier_locations_history
      (user_id, order_id, lat, lon, accuracy, speed, heading, recorded_at)
    VALUES
      (v_user_id, v_order_id, p_lat, p_lng, p_accuracy, p_speed, p_heading, v_now);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_my_location(double precision, double precision, double precision, double precision, double precision, uuid) TO authenticated;


-- Authorized fetch of driver location for a given order
-- Ensure we can change the return type safely across deployments
DROP FUNCTION IF EXISTS public.get_driver_location_for_order(uuid);
CREATE OR REPLACE FUNCTION public.get_driver_location_for_order(
  p_order_id uuid
)
RETURNS TABLE(lat double precision, lng double precision, updated_at timestamptz, bearing double precision, speed double precision)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_driver_id uuid;
  v_user_role text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT o.delivery_agent_id INTO v_driver_id
  FROM public.orders o
  WHERE o.id = p_order_id;

  IF v_driver_id IS NULL THEN
    -- Return empty set
    RETURN;
  END IF;

  SELECT lower(coalesce(u.role, 'client')) INTO v_user_role
  FROM public.users u
  WHERE u.id = v_uid;

  -- Authorization: self, client of the order, restaurant owner, or admin
  IF v_uid = v_driver_id
     OR EXISTS (
          SELECT 1 FROM public.orders o
          WHERE o.id = p_order_id
            AND o.user_id = v_uid
        )
     OR EXISTS (
          SELECT 1
          FROM public.orders o
          JOIN public.restaurants r ON r.id = o.restaurant_id
          WHERE o.id = p_order_id
            AND r.user_id = v_uid
        )
     OR v_user_role = 'admin'
  THEN
    RETURN QUERY
    SELECT l.lat, l.lon AS lng, l.last_seen_at AS updated_at, l.heading AS bearing, l.speed
    FROM public.courier_locations_latest l
    WHERE l.user_id = v_driver_id;
  ELSE
    RAISE EXCEPTION 'not allowed';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_driver_location_for_order(uuid) TO authenticated;
