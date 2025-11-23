-- Row Level Security policies for live location tables

-- Helpers: active delivery statuses used by your app
-- Adjust if your orders.status set changes
CREATE OR REPLACE FUNCTION public._is_active_delivery_status(p_status text)
RETURNS boolean
LANGUAGE sql
AS $$
  SELECT lower(p_status) IN ('assigned','ready_for_pickup','on_the_way','en_camino');
$$;

-- Latest table policies
DROP POLICY IF EXISTS courier_latest_write_self ON public.courier_locations_latest;
CREATE POLICY courier_latest_write_self
ON public.courier_locations_latest
AS PERMISSIVE
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS courier_latest_update_self ON public.courier_locations_latest;
CREATE POLICY courier_latest_update_self
ON public.courier_locations_latest
AS PERMISSIVE
FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Read by self
DROP POLICY IF EXISTS courier_latest_select_self ON public.courier_locations_latest;
CREATE POLICY courier_latest_select_self
ON public.courier_locations_latest
AS PERMISSIVE
FOR SELECT TO authenticated
USING (auth.uid() = user_id);

-- Read by client of active order
DROP POLICY IF EXISTS courier_latest_select_client ON public.courier_locations_latest;
CREATE POLICY courier_latest_select_client
ON public.courier_locations_latest
AS PERMISSIVE
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.delivery_agent_id = courier_locations_latest.user_id
      AND o.user_id = auth.uid()
      AND public._is_active_delivery_status(o.status)
  )
);

-- Read by restaurant owner of active order
DROP POLICY IF EXISTS courier_latest_select_restaurant ON public.courier_locations_latest;
CREATE POLICY courier_latest_select_restaurant
ON public.courier_locations_latest
AS PERMISSIVE
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.orders o
    JOIN public.restaurants r ON r.id = o.restaurant_id
    WHERE o.delivery_agent_id = courier_locations_latest.user_id
      AND r.user_id = auth.uid()
      AND public._is_active_delivery_status(o.status)
  )
);

-- Read by admins
DROP POLICY IF EXISTS courier_latest_select_admin ON public.courier_locations_latest;
CREATE POLICY courier_latest_select_admin
ON public.courier_locations_latest
AS PERMISSIVE
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid()
      AND lower(coalesce(u.role,'client')) IN ('admin')
  )
);

-- History table: driver writes own rows (RPC also writes under definer)
DROP POLICY IF EXISTS courier_hist_insert_self ON public.courier_locations_history;
CREATE POLICY courier_hist_insert_self
ON public.courier_locations_history
AS PERMISSIVE
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Optional: mirror read policies from latest (uncomment to enable)
-- DROP POLICY IF EXISTS courier_hist_select_self ON public.courier_locations_history;
-- CREATE POLICY courier_hist_select_self
-- ON public.courier_locations_history
-- AS PERMISSIVE
-- FOR SELECT TO authenticated
-- USING (auth.uid() = user_id);
