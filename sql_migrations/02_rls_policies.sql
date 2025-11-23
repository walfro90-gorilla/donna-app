-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- Controla el acceso a nivel de fila para cada tabla
-- ============================================================================

-- ============================================================================
-- HABILITAR RLS EN TODAS LAS TABLAS
-- ============================================================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_agent_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_combos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_combo_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_status_updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courier_locations_latest ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courier_locations_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_logs ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- POLICIES: users
-- ============================================================================

-- Usuarios pueden ver su propia información
CREATE POLICY users_select_own ON public.users
  FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

-- Admins pueden ver todos los usuarios
CREATE POLICY users_select_admin ON public.users
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Usuarios pueden actualizar su propia información
CREATE POLICY users_update_own ON public.users
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Admins pueden actualizar cualquier usuario
CREATE POLICY users_update_admin ON public.users
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Permitir insert público (para registro)
CREATE POLICY users_insert_public ON public.users
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- ============================================================================
-- POLICIES: client_profiles
-- ============================================================================

CREATE POLICY client_profiles_select_own ON public.client_profiles
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY client_profiles_insert_own ON public.client_profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY client_profiles_update_own ON public.client_profiles
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ============================================================================
-- POLICIES: delivery_agent_profiles
-- ============================================================================

CREATE POLICY delivery_profiles_select_own ON public.delivery_agent_profiles
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY delivery_profiles_select_admin ON public.delivery_agent_profiles
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY delivery_profiles_insert_own ON public.delivery_agent_profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY delivery_profiles_update_own ON public.delivery_agent_profiles
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY delivery_profiles_update_admin ON public.delivery_agent_profiles
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- ============================================================================
-- POLICIES: restaurants
-- ============================================================================

-- Cualquiera puede ver restaurantes aprobados y online
CREATE POLICY restaurants_select_public ON public.restaurants
  FOR SELECT
  TO authenticated, anon
  USING (status = 'approved' OR user_id = auth.uid());

-- Restaurante puede ver su propia información
CREATE POLICY restaurants_select_own ON public.restaurants
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Admins pueden ver todos los restaurantes
CREATE POLICY restaurants_select_admin ON public.restaurants
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Restaurantes pueden actualizar su información
CREATE POLICY restaurants_update_own ON public.restaurants
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Admins pueden actualizar cualquier restaurante
CREATE POLICY restaurants_update_admin ON public.restaurants
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Permitir insert público (para registro)
CREATE POLICY restaurants_insert_public ON public.restaurants
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- ============================================================================
-- POLICIES: products
-- ============================================================================

-- Cualquiera puede ver productos disponibles de restaurantes aprobados
CREATE POLICY products_select_public ON public.products
  FOR SELECT
  TO authenticated, anon
  USING (
    is_available = true AND EXISTS (
      SELECT 1 FROM public.restaurants 
      WHERE id = restaurant_id AND status = 'approved'
    )
  );

-- Restaurante puede ver sus propios productos
CREATE POLICY products_select_own ON public.products
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.restaurants 
      WHERE id = restaurant_id AND user_id = auth.uid()
    )
  );

-- Restaurante puede insertar/actualizar/eliminar sus productos
CREATE POLICY products_insert_own ON public.products
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.restaurants 
      WHERE id = restaurant_id AND user_id = auth.uid()
    )
  );

CREATE POLICY products_update_own ON public.products
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.restaurants 
      WHERE id = restaurant_id AND user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.restaurants 
      WHERE id = restaurant_id AND user_id = auth.uid()
    )
  );

CREATE POLICY products_delete_own ON public.products
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.restaurants 
      WHERE id = restaurant_id AND user_id = auth.uid()
    )
  );

-- ============================================================================
-- POLICIES: product_combos y product_combo_items
-- ============================================================================

CREATE POLICY combos_select_public ON public.product_combos
  FOR SELECT
  TO authenticated, anon
  USING (
    EXISTS (
      SELECT 1 FROM public.restaurants 
      WHERE id = restaurant_id AND status = 'approved'
    )
  );

CREATE POLICY combos_all_own ON public.product_combos
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.restaurants 
      WHERE id = restaurant_id AND user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.restaurants 
      WHERE id = restaurant_id AND user_id = auth.uid()
    )
  );

CREATE POLICY combo_items_select_public ON public.product_combo_items
  FOR SELECT
  TO authenticated, anon
  USING (true);

CREATE POLICY combo_items_all_own ON public.product_combo_items
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.product_combos pc
      JOIN public.restaurants r ON pc.restaurant_id = r.id
      WHERE pc.id = combo_id AND r.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.product_combos pc
      JOIN public.restaurants r ON pc.restaurant_id = r.id
      WHERE pc.id = combo_id AND r.user_id = auth.uid()
    )
  );

-- ============================================================================
-- POLICIES: orders
-- ============================================================================

-- Cliente puede ver sus propias órdenes
CREATE POLICY orders_select_client ON public.orders
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Restaurante puede ver órdenes de su restaurante
CREATE POLICY orders_select_restaurant ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.restaurants 
      WHERE id = restaurant_id AND user_id = auth.uid()
    )
  );

-- Repartidor puede ver órdenes asignadas a él
CREATE POLICY orders_select_delivery ON public.orders
  FOR SELECT
  TO authenticated
  USING (delivery_agent_id = auth.uid());

-- Admins pueden ver todas las órdenes
CREATE POLICY orders_select_admin ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Cliente puede crear órdenes
CREATE POLICY orders_insert_client ON public.orders
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Restaurante puede actualizar órdenes de su restaurante
CREATE POLICY orders_update_restaurant ON public.orders
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.restaurants 
      WHERE id = restaurant_id AND user_id = auth.uid()
    )
  );

-- Repartidor puede actualizar órdenes asignadas a él
CREATE POLICY orders_update_delivery ON public.orders
  FOR UPDATE
  TO authenticated
  USING (delivery_agent_id = auth.uid());

-- Admin puede actualizar cualquier orden
CREATE POLICY orders_update_admin ON public.orders
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- ============================================================================
-- POLICIES: order_items
-- ============================================================================

CREATE POLICY order_items_select ON public.order_items
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id 
      AND (
        o.user_id = auth.uid() 
        OR o.delivery_agent_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.restaurants r 
          WHERE r.id = o.restaurant_id AND r.user_id = auth.uid()
        )
        OR EXISTS (
          SELECT 1 FROM public.users u 
          WHERE u.id = auth.uid() AND u.role = 'admin'
        )
      )
    )
  );

CREATE POLICY order_items_insert ON public.order_items
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders 
      WHERE id = order_id AND user_id = auth.uid()
    )
  );

-- ============================================================================
-- POLICIES: order_status_updates
-- ============================================================================

CREATE POLICY order_status_select ON public.order_status_updates
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id 
      AND (
        o.user_id = auth.uid() 
        OR o.delivery_agent_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.restaurants r 
          WHERE r.id = o.restaurant_id AND r.user_id = auth.uid()
        )
        OR EXISTS (
          SELECT 1 FROM public.users u 
          WHERE u.id = auth.uid() AND u.role = 'admin'
        )
      )
    )
  );

CREATE POLICY order_status_insert ON public.order_status_updates
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- ============================================================================
-- POLICIES: payments
-- ============================================================================

CREATE POLICY payments_select ON public.payments
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id 
      AND (
        o.user_id = auth.uid() 
        OR EXISTS (
          SELECT 1 FROM public.restaurants r 
          WHERE r.id = o.restaurant_id AND r.user_id = auth.uid()
        )
        OR EXISTS (
          SELECT 1 FROM public.users u 
          WHERE u.id = auth.uid() AND u.role = 'admin'
        )
      )
    )
  );

CREATE POLICY payments_insert ON public.payments
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders 
      WHERE id = order_id AND user_id = auth.uid()
    )
  );

-- ============================================================================
-- POLICIES: accounts
-- ============================================================================

CREATE POLICY accounts_select_own ON public.accounts
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY accounts_select_admin ON public.accounts
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY accounts_insert_own ON public.accounts
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY accounts_update_system ON public.accounts
  FOR UPDATE
  TO authenticated
  USING (true);

-- ============================================================================
-- POLICIES: account_transactions
-- ============================================================================

CREATE POLICY transactions_select_own ON public.account_transactions
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.accounts 
      WHERE id = account_id AND user_id = auth.uid()
    )
  );

CREATE POLICY transactions_select_admin ON public.account_transactions
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY transactions_insert ON public.account_transactions
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- ============================================================================
-- POLICIES: settlements
-- ============================================================================

CREATE POLICY settlements_select_involved ON public.settlements
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.accounts 
      WHERE (id = payer_account_id OR id = receiver_account_id) 
      AND user_id = auth.uid()
    )
  );

CREATE POLICY settlements_select_admin ON public.settlements
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY settlements_insert ON public.settlements
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.accounts 
      WHERE id = payer_account_id AND user_id = auth.uid()
    )
  );

CREATE POLICY settlements_update_involved ON public.settlements
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.accounts 
      WHERE (id = payer_account_id OR id = receiver_account_id) 
      AND user_id = auth.uid()
    )
  );

CREATE POLICY settlements_update_admin ON public.settlements
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- ============================================================================
-- POLICIES: courier_locations_latest
-- ============================================================================

-- Repartidor puede actualizar su ubicación
CREATE POLICY courier_location_update_own ON public.courier_locations_latest
  FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Cliente puede ver ubicación del repartidor de su orden
CREATE POLICY courier_location_select_client ON public.courier_locations_latest
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders 
      WHERE delivery_agent_id = courier_locations_latest.user_id 
      AND user_id = auth.uid()
    )
  );

-- Restaurante puede ver ubicación de repartidores de sus órdenes
CREATE POLICY courier_location_select_restaurant ON public.courier_locations_latest
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      JOIN public.restaurants r ON o.restaurant_id = r.id
      WHERE o.delivery_agent_id = courier_locations_latest.user_id 
      AND r.user_id = auth.uid()
    )
  );

-- Admin puede ver todas las ubicaciones
CREATE POLICY courier_location_select_admin ON public.courier_locations_latest
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- ============================================================================
-- POLICIES: courier_locations_history
-- ============================================================================

CREATE POLICY courier_history_insert ON public.courier_locations_history
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY courier_history_select_own ON public.courier_locations_history
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY courier_history_select_admin ON public.courier_locations_history
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- ============================================================================
-- POLICIES: reviews
-- ============================================================================

CREATE POLICY reviews_select_public ON public.reviews
  FOR SELECT
  TO authenticated, anon
  USING (true);

CREATE POLICY reviews_insert_own ON public.reviews
  FOR INSERT
  TO authenticated
  WITH CHECK (reviewer_id = auth.uid());

CREATE POLICY reviews_update_own ON public.reviews
  FOR UPDATE
  TO authenticated
  USING (reviewer_id = auth.uid())
  WITH CHECK (reviewer_id = auth.uid());

-- ============================================================================
-- POLICIES: app_logs
-- ============================================================================

CREATE POLICY app_logs_insert ON public.app_logs
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

CREATE POLICY app_logs_select_admin ON public.app_logs
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );
