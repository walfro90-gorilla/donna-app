-- =====================================================
-- FASE 2: CORRECCIÓN DE POLÍTICAS RLS
-- =====================================================
-- Propósito: Reescribir todas las políticas RLS con tipos correctos
-- Orden: Debe ejecutarse SEGUNDO (después de limpiar datos)
-- =====================================================

-- =====================================================
-- 1. ELIMINAR TODAS LAS POLÍTICAS EXISTENTES
-- =====================================================

-- Users
DROP POLICY IF EXISTS "users_select_own" ON public.users;
DROP POLICY IF EXISTS "users_update_own" ON public.users;
DROP POLICY IF EXISTS "users_insert_own" ON public.users;
DROP POLICY IF EXISTS "admin_full_users" ON public.users;

-- Restaurants
DROP POLICY IF EXISTS "restaurants_select_all" ON public.restaurants;
DROP POLICY IF EXISTS "restaurants_insert_own" ON public.restaurants;
DROP POLICY IF EXISTS "restaurants_update_own" ON public.restaurants;
DROP POLICY IF EXISTS "admin_full_restaurants" ON public.restaurants;

-- Products
DROP POLICY IF EXISTS "products_select_all" ON public.products;
DROP POLICY IF EXISTS "products_insert_own_restaurant" ON public.products;
DROP POLICY IF EXISTS "products_update_own_restaurant" ON public.products;
DROP POLICY IF EXISTS "products_delete_own_restaurant" ON public.products;

-- Orders
DROP POLICY IF EXISTS "orders_select_own" ON public.orders;
DROP POLICY IF EXISTS "orders_select_restaurant" ON public.orders;
DROP POLICY IF EXISTS "orders_select_delivery" ON public.orders;
DROP POLICY IF EXISTS "orders_insert_own" ON public.orders;
DROP POLICY IF EXISTS "orders_update_own" ON public.orders;
DROP POLICY IF EXISTS "orders_update_restaurant" ON public.orders;
DROP POLICY IF EXISTS "orders_update_delivery" ON public.orders;
DROP POLICY IF EXISTS "admin_full_orders" ON public.orders;

-- Order Items
DROP POLICY IF EXISTS "order_items_select_own" ON public.order_items;
DROP POLICY IF EXISTS "order_items_insert_own" ON public.order_items;

-- Order Status Updates
DROP POLICY IF EXISTS "order_status_select_related" ON public.order_status_updates;
DROP POLICY IF EXISTS "order_status_insert_related" ON public.order_status_updates;

-- Payments
DROP POLICY IF EXISTS "payments_select_own" ON public.payments;
DROP POLICY IF EXISTS "payments_insert_system" ON public.payments;

-- Accounts
DROP POLICY IF EXISTS "accounts_select_own" ON public.accounts;
DROP POLICY IF EXISTS "accounts_update_system" ON public.accounts;
DROP POLICY IF EXISTS "admin_full_accounts" ON public.accounts;

-- Account Transactions
DROP POLICY IF EXISTS "transactions_select_own" ON public.account_transactions;
DROP POLICY IF EXISTS "transactions_insert_system" ON public.account_transactions;
DROP POLICY IF EXISTS "admin_full_transactions" ON public.account_transactions;

-- Settlements
DROP POLICY IF EXISTS "settlements_select_related" ON public.settlements;
DROP POLICY IF EXISTS "settlements_insert_admin" ON public.settlements;
DROP POLICY IF EXISTS "settlements_update_related" ON public.settlements;
DROP POLICY IF EXISTS "admin_full_settlements" ON public.settlements;

-- Reviews
DROP POLICY IF EXISTS "reviews_select_all" ON public.reviews;
DROP POLICY IF EXISTS "reviews_insert_own" ON public.reviews;
DROP POLICY IF EXISTS "reviews_update_own" ON public.reviews;

-- =====================================================
-- 2. HABILITAR RLS EN TODAS LAS TABLAS
-- =====================================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_status_updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- 3. CREAR POLÍTICAS CORREGIDAS - USERS
-- =====================================================

CREATE POLICY "users_select_own" ON public.users
  FOR SELECT USING (id = auth.uid());

CREATE POLICY "users_update_own" ON public.users
  FOR UPDATE USING (id = auth.uid());

CREATE POLICY "users_insert_own" ON public.users
  FOR INSERT WITH CHECK (id = auth.uid());

CREATE POLICY "admin_full_users" ON public.users
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- =====================================================
-- 4. CREAR POLÍTICAS CORREGIDAS - RESTAURANTS
-- =====================================================

CREATE POLICY "restaurants_select_all" ON public.restaurants
  FOR SELECT USING (true);

CREATE POLICY "restaurants_insert_own" ON public.restaurants
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "restaurants_update_own" ON public.restaurants
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "admin_full_restaurants" ON public.restaurants
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- =====================================================
-- 5. CREAR POLÍTICAS CORREGIDAS - PRODUCTS
-- =====================================================

CREATE POLICY "products_select_all" ON public.products
  FOR SELECT USING (true);

CREATE POLICY "products_insert_own_restaurant" ON public.products
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id = restaurant_id AND r.user_id = auth.uid()
    )
  );

CREATE POLICY "products_update_own_restaurant" ON public.products
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id = restaurant_id AND r.user_id = auth.uid()
    )
  );

CREATE POLICY "products_delete_own_restaurant" ON public.products
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id = restaurant_id AND r.user_id = auth.uid()
    )
  );

-- =====================================================
-- 6. CREAR POLÍTICAS CORREGIDAS - ORDERS
-- =====================================================

CREATE POLICY "orders_select_own" ON public.orders
  FOR SELECT USING (
    user_id = auth.uid()
    OR delivery_agent_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id = restaurant_id AND r.user_id = auth.uid()
    )
  );

CREATE POLICY "orders_insert_own" ON public.orders
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "orders_update_own" ON public.orders
  FOR UPDATE USING (
    user_id = auth.uid()
    OR delivery_agent_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id = restaurant_id AND r.user_id = auth.uid()
    )
  );

CREATE POLICY "admin_full_orders" ON public.orders
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- =====================================================
-- 7. CREAR POLÍTICAS CORREGIDAS - ORDER ITEMS
-- =====================================================

CREATE POLICY "order_items_select_own" ON public.order_items
  FOR SELECT USING (
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
      )
    )
  );

CREATE POLICY "order_items_insert_own" ON public.order_items
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id AND o.user_id = auth.uid()
    )
  );

-- =====================================================
-- 8. CREAR POLÍTICAS CORREGIDAS - ORDER STATUS UPDATES
-- =====================================================

CREATE POLICY "order_status_select_related" ON public.order_status_updates
  FOR SELECT USING (
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
      )
    )
  );

CREATE POLICY "order_status_insert_related" ON public.order_status_updates
  FOR INSERT WITH CHECK (
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
      )
    )
  );

-- =====================================================
-- 9. CREAR POLÍTICAS CORREGIDAS - PAYMENTS
-- =====================================================

CREATE POLICY "payments_select_own" ON public.payments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_id AND o.user_id = auth.uid()
    )
  );

CREATE POLICY "payments_insert_system" ON public.payments
  FOR INSERT WITH CHECK (true);

-- =====================================================
-- 10. CREAR POLÍTICAS CORREGIDAS - ACCOUNTS
-- =====================================================

CREATE POLICY "accounts_select_own" ON public.accounts
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "accounts_update_system" ON public.accounts
  FOR UPDATE USING (true);

CREATE POLICY "admin_full_accounts" ON public.accounts
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- =====================================================
-- 11. CREAR POLÍTICAS CORREGIDAS - ACCOUNT TRANSACTIONS
-- =====================================================

CREATE POLICY "transactions_select_own" ON public.account_transactions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.accounts a
      WHERE a.id = account_id AND a.user_id = auth.uid()
    )
  );

CREATE POLICY "transactions_insert_system" ON public.account_transactions
  FOR INSERT WITH CHECK (true);

CREATE POLICY "admin_full_transactions" ON public.account_transactions
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- =====================================================
-- 12. CREAR POLÍTICAS CORREGIDAS - SETTLEMENTS
-- =====================================================

CREATE POLICY "settlements_select_related" ON public.settlements
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.accounts a
      WHERE (a.id = payer_account_id OR a.id = receiver_account_id)
      AND a.user_id = auth.uid()
    )
  );

CREATE POLICY "settlements_insert_admin" ON public.settlements
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

CREATE POLICY "settlements_update_related" ON public.settlements
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.accounts a
      WHERE (a.id = payer_account_id OR a.id = receiver_account_id)
      AND a.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

CREATE POLICY "admin_full_settlements" ON public.settlements
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- =====================================================
-- 13. CREAR POLÍTICAS CORREGIDAS - REVIEWS
-- =====================================================

CREATE POLICY "reviews_select_all" ON public.reviews
  FOR SELECT USING (true);

CREATE POLICY "reviews_insert_own" ON public.reviews
  FOR INSERT WITH CHECK (author_id = auth.uid());

CREATE POLICY "reviews_update_own" ON public.reviews
  FOR UPDATE USING (author_id = auth.uid());

-- =====================================================
-- ✅ POLÍTICAS RLS CORREGIDAS Y APLICADAS
-- =====================================================
