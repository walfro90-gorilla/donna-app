-- ================================================================
-- FIX LOCATION TRACKING: Create update_my_location RPC function
-- ================================================================
-- This script creates the missing RPC function that the Flutter app calls
-- to send driver geolocation updates.
--
-- PREREQUISITE: Tables courier_locations_latest and courier_locations_history
-- must exist (they are already in DATABASE_SCHEMA.sql)
--
-- USAGE: Copy/paste into Supabase SQL Editor and run
-- ================================================================

-- ================================================================
-- 1. DROP EXISTING FUNCTIONS (if any)
-- ================================================================
DO $$
DECLARE
  func_sig TEXT;
BEGIN
  -- Drop all variants of update_my_location
  FOR func_sig IN
    SELECT 
      'public.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname = 'update_my_location'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || func_sig || ' CASCADE';
    RAISE NOTICE 'Dropped function: %', func_sig;
  END LOOP;

  -- Drop all variants of get_driver_location_for_order
  FOR func_sig IN
    SELECT 
      'public.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname = 'get_driver_location_for_order'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || func_sig || ' CASCADE';
    RAISE NOTICE 'Dropped function: %', func_sig;
  END LOOP;
END $$;

-- ================================================================
-- 2. CREATE FUNCTION update_my_location
-- ================================================================
-- Inserts/updates driver location in courier_locations_latest (current position)
-- and appends to courier_locations_history (breadcrumb trail).
--
-- Parameters:
--   p_lat: latitude (double precision)
--   p_lng: longitude (double precision)
--
-- Returns: void
-- Security: SECURITY DEFINER (runs with elevated privileges to bypass RLS)
-- ================================================================

CREATE OR REPLACE FUNCTION public.update_my_location(
  p_lat double precision,
  p_lng double precision
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_active_order_id UUID;
BEGIN
  -- Get authenticated user ID
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Find the driver's active order (assigned, picked_up, or in_transit)
  SELECT id INTO v_active_order_id
  FROM public.orders
  WHERE delivery_agent_id = v_user_id
    AND status IN ('assigned', 'ready_for_pickup', 'picked_up', 'in_transit', 'on_the_way')
  ORDER BY updated_at DESC
  LIMIT 1;

  -- UPSERT into courier_locations_latest (current position)
  INSERT INTO public.courier_locations_latest (
    user_id,
    order_id,
    lat,
    lon,
    source,
    last_seen_at
  ) VALUES (
    v_user_id,
    v_active_order_id,
    p_lat,
    p_lng,
    'app',
    NOW()
  )
  ON CONFLICT (user_id)
  DO UPDATE SET
    order_id = EXCLUDED.order_id,
    lat = EXCLUDED.lat,
    lon = EXCLUDED.lon,
    source = EXCLUDED.source,
    last_seen_at = EXCLUDED.last_seen_at;

  -- INSERT into courier_locations_history (breadcrumb trail)
  INSERT INTO public.courier_locations_history (
    user_id,
    order_id,
    lat,
    lon,
    recorded_at
  ) VALUES (
    v_user_id,
    v_active_order_id,
    p_lat,
    p_lng,
    NOW()
  );

END $$;

-- ================================================================
-- 3. CREATE FUNCTION get_driver_location_for_order
-- ================================================================
-- Returns the current location of the driver assigned to an order.
-- Called by clients, restaurants, and admins to track delivery in real-time.
--
-- Parameters:
--   p_order_id: UUID of the order
--
-- Returns: TABLE with lat, lon, last_seen_at, speed, heading, accuracy
-- Security: SECURITY DEFINER (bypasses RLS, but checks authorization internally)
-- ================================================================

CREATE OR REPLACE FUNCTION public.get_driver_location_for_order(
  p_order_id UUID
)
RETURNS TABLE (
  lat double precision,
  lon double precision,
  last_seen_at timestamp with time zone,
  speed double precision,
  heading double precision,
  accuracy double precision
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delivery_agent_id UUID;
  v_requester_id UUID;
  v_is_authorized BOOLEAN := FALSE;
BEGIN
  v_requester_id := auth.uid();
  
  IF v_requester_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Get the delivery agent ID for this order
  SELECT delivery_agent_id INTO v_delivery_agent_id
  FROM public.orders
  WHERE id = p_order_id;

  IF v_delivery_agent_id IS NULL THEN
    -- No driver assigned yet
    RETURN;
  END IF;

  -- Check authorization: requester must be the client, the restaurant owner, or an admin
  SELECT EXISTS (
    -- Case 1: requester is the client who placed the order
    SELECT 1 FROM public.orders o
    WHERE o.id = p_order_id AND o.user_id = v_requester_id
    
    UNION
    
    -- Case 2: requester is the restaurant owner
    SELECT 1 FROM public.orders o
    JOIN public.restaurants r ON o.restaurant_id = r.id
    WHERE o.id = p_order_id AND r.user_id = v_requester_id
    
    UNION
    
    -- Case 3: requester is an admin
    SELECT 1 FROM public.users u
    WHERE u.id = v_requester_id AND u.role = 'admin'
  ) INTO v_is_authorized;

  IF NOT v_is_authorized THEN
    RAISE EXCEPTION 'Unauthorized to view this driver location';
  END IF;

  -- Return the driver's current location from courier_locations_latest
  RETURN QUERY
  SELECT 
    cll.lat,
    cll.lon,
    cll.last_seen_at,
    cll.speed,
    cll.heading,
    cll.accuracy
  FROM public.courier_locations_latest cll
  WHERE cll.user_id = v_delivery_agent_id;
END $$;

-- ================================================================
-- 4. GRANT EXECUTE PERMISSIONS
-- ================================================================
-- Allow authenticated users to call these functions
GRANT EXECUTE ON FUNCTION public.update_my_location(double precision, double precision) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_driver_location_for_order(UUID) TO authenticated;

-- ================================================================
-- 5. ENABLE RLS ON TABLES (if not already enabled)
-- ================================================================
ALTER TABLE public.courier_locations_latest ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courier_locations_history ENABLE ROW LEVEL SECURITY;

-- ================================================================
-- 6. RLS POLICIES FOR courier_locations_latest
-- ================================================================

-- Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "Drivers can update their own location" ON public.courier_locations_latest;
DROP POLICY IF EXISTS "Clients can view driver location for their orders" ON public.courier_locations_latest;
DROP POLICY IF EXISTS "Restaurants can view driver location for their orders" ON public.courier_locations_latest;
DROP POLICY IF EXISTS "Admins can view all driver locations" ON public.courier_locations_latest;

-- Policy 1: Drivers can insert/update their own location
CREATE POLICY "Drivers can update their own location"
ON public.courier_locations_latest
FOR ALL
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Policy 2: Clients can view driver location for their active orders
CREATE POLICY "Clients can view driver location for their orders"
ON public.courier_locations_latest
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.delivery_agent_id = courier_locations_latest.user_id
      AND o.user_id = auth.uid()
      AND o.status IN ('assigned', 'ready_for_pickup', 'picked_up', 'in_transit', 'on_the_way')
  )
);

-- Policy 3: Restaurants can view driver location for their active orders
CREATE POLICY "Restaurants can view driver location for their orders"
ON public.courier_locations_latest
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.orders o
    JOIN public.restaurants r ON o.restaurant_id = r.id
    WHERE o.delivery_agent_id = courier_locations_latest.user_id
      AND r.user_id = auth.uid()
      AND o.status IN ('assigned', 'ready_for_pickup', 'picked_up', 'in_transit', 'on_the_way')
  )
);

-- Policy 4: Admins can view all driver locations
CREATE POLICY "Admins can view all driver locations"
ON public.courier_locations_latest
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  )
);

-- ================================================================
-- 7. RLS POLICIES FOR courier_locations_history
-- ================================================================

-- Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "Drivers can insert their own location history" ON public.courier_locations_history;
DROP POLICY IF EXISTS "Clients can view driver location history for their orders" ON public.courier_locations_history;
DROP POLICY IF EXISTS "Restaurants can view driver location history for their orders" ON public.courier_locations_history;
DROP POLICY IF EXISTS "Admins can view all driver location history" ON public.courier_locations_history;

-- Policy 1: Drivers can insert their own location history
CREATE POLICY "Drivers can insert their own location history"
ON public.courier_locations_history
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Policy 2: Clients can view driver location history for their orders
CREATE POLICY "Clients can view driver location history for their orders"
ON public.courier_locations_history
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.delivery_agent_id = courier_locations_history.user_id
      AND o.user_id = auth.uid()
      AND o.id = courier_locations_history.order_id
  )
);

-- Policy 3: Restaurants can view driver location history for their orders
CREATE POLICY "Restaurants can view driver location history for their orders"
ON public.courier_locations_history
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.orders o
    JOIN public.restaurants r ON o.restaurant_id = r.id
    WHERE o.delivery_agent_id = courier_locations_history.user_id
      AND r.user_id = auth.uid()
      AND o.id = courier_locations_history.order_id
  )
);

-- Policy 4: Admins can view all driver location history
CREATE POLICY "Admins can view all driver location history"
ON public.courier_locations_history
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  )
);

-- ================================================================
-- 8. ENABLE REALTIME FOR courier_locations_latest
-- ================================================================
-- This allows Flutter app to subscribe to live location updates via Supabase Realtime
-- Skip if already added (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
      AND schemaname = 'public' 
      AND tablename = 'courier_locations_latest'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.courier_locations_latest;
    RAISE NOTICE 'Added courier_locations_latest to supabase_realtime publication';
  ELSE
    RAISE NOTICE 'courier_locations_latest already in supabase_realtime publication';
  END IF;
END $$;

-- ================================================================
-- 9. RELOAD SCHEMA CACHE
-- ================================================================
-- Force PostgREST to reload the schema cache so the new function is immediately available
NOTIFY pgrst, 'reload schema';

-- ================================================================
-- DONE! 
-- ================================================================
-- Created RPCs:
--   1. update_my_location(p_lat, p_lng) - Driver sends location updates
--   2. get_driver_location_for_order(p_order_id) - Clients/restaurants/admins read driver location
--
-- Tables affected:
--   - courier_locations_latest (current position)
--   - courier_locations_history (breadcrumb trail)
--
-- The schema cache has been reloaded. Functions are now available via PostgREST.
-- ================================================================
