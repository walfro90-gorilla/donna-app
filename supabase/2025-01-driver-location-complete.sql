-- ========================================================================
-- DRIVER LOCATION TRACKING - Complete Schema & Functions
-- ========================================================================
-- Purpose: Store and retrieve courier real-time location for order tracking
-- Compatible with DATABASE_SCHEMA.sql
-- Run this ONCE in Supabase SQL Editor
-- ========================================================================

-- ========================================================================
-- 0. CLEANUP: Drop all existing function variations FIRST
-- ========================================================================

-- Drop update_my_location variations
DO $$ 
DECLARE
  func_rec RECORD;
BEGIN
  FOR func_rec IN 
    SELECT oid::regprocedure::text AS func_sig
    FROM pg_proc 
    WHERE proname = 'update_my_location' 
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || func_rec.func_sig || ' CASCADE';
  END LOOP;
END $$;

-- Drop get_driver_location_for_order variations
DO $$ 
DECLARE
  func_rec RECORD;
BEGIN
  FOR func_rec IN 
    SELECT oid::regprocedure::text AS func_sig
    FROM pg_proc 
    WHERE proname = 'get_driver_location_for_order' 
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || func_rec.func_sig || ' CASCADE';
  END LOOP;
END $$;

-- ========================================================================
-- 1. TABLES (Adjusted to match existing DATABASE_SCHEMA.sql)
-- ========================================================================

-- Table: courier_locations_latest (current position, one row per driver)
-- Matches DATABASE_SCHEMA.sql columns exactly
CREATE TABLE IF NOT EXISTS public.courier_locations_latest (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  order_id UUID REFERENCES public.orders(id),
  lat DOUBLE PRECISION NOT NULL,
  lon DOUBLE PRECISION NOT NULL,
  accuracy DOUBLE PRECISION,
  speed DOUBLE PRECISION,
  heading DOUBLE PRECISION,
  source TEXT,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table: courier_locations_history (breadcrumb trail)
-- Matches DATABASE_SCHEMA.sql columns exactly
CREATE TABLE IF NOT EXISTS public.courier_locations_history (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  order_id UUID REFERENCES public.orders(id),
  lat DOUBLE PRECISION NOT NULL,
  lon DOUBLE PRECISION NOT NULL,
  accuracy DOUBLE PRECISION,
  speed DOUBLE PRECISION,
  heading DOUBLE PRECISION,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ========================================================================
-- 2. INDEXES
-- ========================================================================

CREATE INDEX IF NOT EXISTS idx_courier_locations_history_user_id 
  ON public.courier_locations_history(user_id);

CREATE INDEX IF NOT EXISTS idx_courier_locations_history_recorded_at 
  ON public.courier_locations_history(recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_courier_locations_history_order_id 
  ON public.courier_locations_history(order_id);

CREATE INDEX IF NOT EXISTS idx_courier_locations_latest_order_id 
  ON public.courier_locations_latest(order_id);

-- ========================================================================
-- 3. ROW LEVEL SECURITY (RLS)
-- ========================================================================

ALTER TABLE public.courier_locations_latest ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courier_locations_history ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any (idempotent)
DROP POLICY IF EXISTS "Drivers can upsert their own location" ON public.courier_locations_latest;
DROP POLICY IF EXISTS "Authorized users can read driver location" ON public.courier_locations_latest;
DROP POLICY IF EXISTS "Admins can read all locations" ON public.courier_locations_latest;

DROP POLICY IF EXISTS "Drivers can insert their own history" ON public.courier_locations_history;
DROP POLICY IF EXISTS "Authorized users can read driver history" ON public.courier_locations_history;
DROP POLICY IF EXISTS "Admins can read all history" ON public.courier_locations_history;

-- POLICIES: courier_locations_latest
CREATE POLICY "Drivers can upsert their own location"
  ON public.courier_locations_latest
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Authorized users can read driver location"
  ON public.courier_locations_latest
  FOR SELECT
  TO authenticated
  USING (
    -- Customer or restaurant of an active order with this driver
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.delivery_agent_id = courier_locations_latest.user_id
        AND o.status IN ('pending', 'confirmed', 'preparing', 'in_preparation', 'ready_for_pickup', 'assigned', 'picked_up', 'on_the_way', 'in_transit')
        AND (o.user_id = auth.uid() OR o.restaurant_id IN (
          SELECT r.id FROM public.restaurants r WHERE r.user_id = auth.uid()
        ))
    )
  );

CREATE POLICY "Admins can read all locations"
  ON public.courier_locations_latest
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users u 
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- POLICIES: courier_locations_history
CREATE POLICY "Drivers can insert their own history"
  ON public.courier_locations_history
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Authorized users can read driver history"
  ON public.courier_locations_history
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.delivery_agent_id = courier_locations_history.user_id
        AND (o.user_id = auth.uid() OR o.restaurant_id IN (
          SELECT r.id FROM public.restaurants r WHERE r.user_id = auth.uid()
        ))
    )
  );

CREATE POLICY "Admins can read all history"
  ON public.courier_locations_history
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users u 
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- ========================================================================
-- 4. REALTIME PUBLICATION
-- ========================================================================

-- Drop existing publication entries (idempotent)
DO $$
BEGIN
  -- Remove tables from publication if already present
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
      AND schemaname = 'public' 
      AND tablename = 'courier_locations_latest'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.courier_locations_latest;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
      AND schemaname = 'public' 
      AND tablename = 'courier_locations_history'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.courier_locations_history;
  END IF;
END $$;

-- Add tables to realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.courier_locations_latest;
ALTER PUBLICATION supabase_realtime ADD TABLE public.courier_locations_history;

-- ========================================================================
-- 5. RPC FUNCTIONS
-- ========================================================================

-- RPC: update_my_location
-- Called by delivery agent to update their current position
CREATE OR REPLACE FUNCTION public.update_my_location(
  p_lat DOUBLE PRECISION,
  p_lon DOUBLE PRECISION,
  p_accuracy DOUBLE PRECISION DEFAULT NULL,
  p_heading DOUBLE PRECISION DEFAULT NULL,
  p_speed DOUBLE PRECISION DEFAULT NULL,
  p_order_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_now TIMESTAMPTZ := NOW();
BEGIN
  -- Validate authenticated user
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Upsert latest location (matches DATABASE_SCHEMA.sql columns)
  INSERT INTO public.courier_locations_latest (user_id, order_id, lat, lon, accuracy, heading, speed, source, last_seen_at)
  VALUES (v_user_id, p_order_id, p_lat, p_lon, p_accuracy, p_heading, p_speed, 'app', v_now)
  ON CONFLICT (user_id) 
  DO UPDATE SET
    order_id = EXCLUDED.order_id,
    lat = EXCLUDED.lat,
    lon = EXCLUDED.lon,
    accuracy = EXCLUDED.accuracy,
    heading = EXCLUDED.heading,
    speed = EXCLUDED.speed,
    source = EXCLUDED.source,
    last_seen_at = EXCLUDED.last_seen_at;

  -- Insert breadcrumb history (matches DATABASE_SCHEMA.sql columns)
  INSERT INTO public.courier_locations_history (user_id, order_id, lat, lon, accuracy, heading, speed, recorded_at)
  VALUES (v_user_id, p_order_id, p_lat, p_lon, p_accuracy, p_heading, p_speed, v_now);

  RETURN json_build_object('success', true, 'last_seen_at', v_now);
END;
$$;

-- RPC: get_driver_location_for_order
-- Returns driver location for a given order (with authorization check)
CREATE OR REPLACE FUNCTION public.get_driver_location_for_order(p_order_id UUID)
RETURNS TABLE(
  driver_id UUID,
  lat DOUBLE PRECISION,
  lon DOUBLE PRECISION,
  accuracy DOUBLE PRECISION,
  heading DOUBLE PRECISION,
  speed DOUBLE PRECISION,
  last_seen_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_order RECORD;
BEGIN
  -- Get order details
  SELECT o.id, o.user_id, o.restaurant_id, o.delivery_agent_id, o.status
  INTO v_order
  FROM public.orders o
  WHERE o.id = p_order_id;

  -- Validate order exists
  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Authorize: customer, restaurant owner, or admin
  IF v_user_id != v_order.user_id 
     AND NOT EXISTS (SELECT 1 FROM public.restaurants r WHERE r.id = v_order.restaurant_id AND r.user_id = v_user_id)
     AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = v_user_id AND u.role = 'admin')
  THEN
    RETURN;
  END IF;

  -- Return driver location if assigned (using DATABASE_SCHEMA.sql column names)
  IF v_order.delivery_agent_id IS NOT NULL THEN
    RETURN QUERY
    SELECT 
      cll.user_id AS driver_id,
      cll.lat,
      cll.lon,
      cll.accuracy,
      cll.heading,
      cll.speed,
      cll.last_seen_at
    FROM public.courier_locations_latest cll
    WHERE cll.user_id = v_order.delivery_agent_id;
  END IF;
END;
$$;

-- ========================================================================
-- 6. COMMENTS
-- ========================================================================

COMMENT ON TABLE public.courier_locations_latest IS 'Current real-time location of delivery agents (one row per driver)';
COMMENT ON TABLE public.courier_locations_history IS 'Historical breadcrumb trail of delivery agent locations';
COMMENT ON FUNCTION public.update_my_location IS 'RPC for delivery agents to update their current location';
COMMENT ON FUNCTION public.get_driver_location_for_order IS 'RPC to get authorized driver location for an order';

-- ========================================================================
-- END OF SCRIPT
-- ========================================================================
