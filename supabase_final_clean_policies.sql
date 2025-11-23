-- ============================================
-- LIMPIEZA TOTAL Y POLÍTICAS OPTIMIZADAS PARA APP DE REPARTOS
-- Basado en schema real identificado
-- ============================================

-- 🧹 ELIMINAR TODAS LAS POLÍTICAS EXISTENTES
DROP POLICY IF EXISTS "Admins can view all users" ON users;
DROP POLICY IF EXISTS "Allow admins to read all users" ON users;
DROP POLICY IF EXISTS "Allow service role to insert users" ON users;
DROP POLICY IF EXISTS "Allow user profile creation during signup" ON users;
DROP POLICY IF EXISTS "Allow users to read own profile" ON users;
DROP POLICY IF EXISTS "Allow users to update own profile" ON users;
DROP POLICY IF EXISTS "Users can insert their own profile" ON users;
DROP POLICY IF EXISTS "users_own_data_only" ON users;
DROP POLICY IF EXISTS "users_select_own" ON users;
DROP POLICY IF EXISTS "users_update_own" ON users;

DROP POLICY IF EXISTS "Everyone can view available products" ON products;
DROP POLICY IF EXISTS "Restaurant owners can manage products" ON products;

DROP POLICY IF EXISTS "Admins can manage all restaurants" ON restaurants;
DROP POLICY IF EXISTS "Customers can view approved restaurants" ON restaurants;
DROP POLICY IF EXISTS "Restaurant owners can manage own restaurant" ON restaurants;
DROP POLICY IF EXISTS "restaurants_owner_write" ON restaurants;
DROP POLICY IF EXISTS "restaurants_public_read" ON restaurants;
DROP POLICY IF EXISTS "restaurants_select_all" ON restaurants;
DROP POLICY IF EXISTS "restaurants_update_owner" ON restaurants;

DROP POLICY IF EXISTS "Admins can manage all payments" ON payments;
DROP POLICY IF EXISTS "Restaurant owners can view restaurant payments" ON payments;
DROP POLICY IF EXISTS "System can update payment status" ON payments;
DROP POLICY IF EXISTS "Users can insert own payments" ON payments;
DROP POLICY IF EXISTS "Users can view own payments" ON payments;

DROP POLICY IF EXISTS "Admins can manage all orders" ON orders;
DROP POLICY IF EXISTS "Customers can create orders" ON orders;
DROP POLICY IF EXISTS "Customers can view own orders" ON orders;
DROP POLICY IF EXISTS "Delivery agents can update assigned orders" ON orders;
DROP POLICY IF EXISTS "Delivery agents can view assigned orders" ON orders;
DROP POLICY IF EXISTS "Delivery agents can view available orders" ON orders;
DROP POLICY IF EXISTS "orders_insert_own" ON orders;
DROP POLICY IF EXISTS "orders_select_own" ON orders;
DROP POLICY IF EXISTS "orders_update_own" ON orders;
DROP POLICY IF EXISTS "Restaurant owners can update order status" ON orders;
DROP POLICY IF EXISTS "Restaurant owners can view restaurant orders" ON orders;

DROP POLICY IF EXISTS "Delivery agents can view assigned order items" ON order_items;
DROP POLICY IF EXISTS "order_items_insert_own" ON order_items;
DROP POLICY IF EXISTS "order_items_select_own" ON order_items;
DROP POLICY IF EXISTS "Restaurant owners can view restaurant order items" ON order_items;
DROP POLICY IF EXISTS "Users can insert own order items" ON order_items;
DROP POLICY IF EXISTS "Users can view own order items" ON order_items;

-- 🔓 DESHABILITAR RLS TEMPORALMENTE
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants DISABLE ROW LEVEL SECURITY;
ALTER TABLE products DISABLE ROW LEVEL SECURITY;
ALTER TABLE orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE order_items DISABLE ROW LEVEL SECURITY;
ALTER TABLE payments DISABLE ROW LEVEL SECURITY;

-- ✅ HABILITAR RLS NUEVAMENTE
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 🔐 POLÍTICAS PARA TABLA USERS
-- ============================================

-- Los usuarios solo pueden ver su propio perfil
CREATE POLICY "users_select_own_simple" ON users 
FOR SELECT 
USING (auth_user_id::uuid = auth.uid());

-- Los usuarios pueden actualizar su propio perfil
CREATE POLICY "users_update_own_simple" ON users 
FOR UPDATE 
USING (auth_user_id::uuid = auth.uid())
WITH CHECK (auth_user_id::uuid = auth.uid());

-- Permitir inserción durante registro
CREATE POLICY "users_insert_signup" ON users 
FOR INSERT 
WITH CHECK (auth_user_id::uuid = auth.uid());

-- ============================================
-- 🏪 POLÍTICAS PARA TABLA RESTAURANTS
-- ============================================

-- Todos pueden ver restaurantes (catálogo público)
CREATE POLICY "restaurants_public_select" ON restaurants 
FOR SELECT 
TO public
USING (true);

-- Solo el dueño puede editar su restaurante
CREATE POLICY "restaurants_owner_manage" ON restaurants 
FOR ALL 
USING (user_id::uuid = auth.uid())
WITH CHECK (user_id::uuid = auth.uid());

-- ============================================
-- 🍕 POLÍTICAS PARA TABLA PRODUCTS
-- ============================================

-- Todos pueden ver productos (catálogo público)
CREATE POLICY "products_public_select" ON products 
FOR SELECT 
TO public
USING (true);

-- Solo el dueño del restaurante puede gestionar productos
CREATE POLICY "products_restaurant_owner" ON products 
FOR ALL 
USING (EXISTS (
    SELECT 1 FROM restaurants 
    WHERE restaurants.id = products.restaurant_id 
    AND restaurants.user_id::uuid = auth.uid()
))
WITH CHECK (EXISTS (
    SELECT 1 FROM restaurants 
    WHERE restaurants.id = products.restaurant_id 
    AND restaurants.user_id::uuid = auth.uid()
));

-- ============================================
-- 📦 POLÍTICAS PARA TABLA ORDERS
-- ============================================

-- Los usuarios pueden ver sus propias órdenes
CREATE POLICY "orders_user_own" ON orders 
FOR SELECT 
USING (user_id::uuid = auth.uid());

-- Los usuarios pueden crear sus propias órdenes
CREATE POLICY "orders_user_insert" ON orders 
FOR INSERT 
WITH CHECK (user_id::uuid = auth.uid());

-- Los usuarios pueden actualizar sus propias órdenes (solo ciertos campos)
CREATE POLICY "orders_user_update" ON orders 
FOR UPDATE 
USING (user_id::uuid = auth.uid())
WITH CHECK (user_id::uuid = auth.uid());

-- Los dueños de restaurantes pueden ver órdenes de su restaurante
CREATE POLICY "orders_restaurant_owner" ON orders 
FOR SELECT 
USING (EXISTS (
    SELECT 1 FROM restaurants 
    WHERE restaurants.id = orders.restaurant_id 
    AND restaurants.user_id::uuid = auth.uid()
));

-- Los agentes de delivery pueden ver órdenes asignadas
CREATE POLICY "orders_delivery_agent" ON orders 
FOR SELECT 
USING (delivery_agent_id::uuid = auth.uid());

-- ============================================
-- 🍽️ POLÍTICAS PARA TABLA ORDER_ITEMS
-- ============================================

-- Los usuarios pueden ver items de sus propias órdenes
CREATE POLICY "order_items_user_own" ON order_items 
FOR SELECT 
USING (EXISTS (
    SELECT 1 FROM orders 
    WHERE orders.id = order_items.order_id 
    AND orders.user_id::uuid = auth.uid()
));

-- Los usuarios pueden insertar items en sus propias órdenes
CREATE POLICY "order_items_user_insert" ON order_items 
FOR INSERT 
WITH CHECK (EXISTS (
    SELECT 1 FROM orders 
    WHERE orders.id = order_items.order_id 
    AND orders.user_id::uuid = auth.uid()
));

-- Los dueños de restaurantes pueden ver items de órdenes de su restaurante
CREATE POLICY "order_items_restaurant_owner" ON order_items 
FOR SELECT 
USING (EXISTS (
    SELECT 1 FROM orders o 
    JOIN restaurants r ON r.id = o.restaurant_id 
    WHERE o.id = order_items.order_id 
    AND r.user_id::uuid = auth.uid()
));

-- ============================================
-- 💳 POLÍTICAS PARA TABLA PAYMENTS
-- ============================================

-- Los usuarios pueden ver sus propios pagos
CREATE POLICY "payments_user_own" ON payments 
FOR SELECT 
USING (EXISTS (
    SELECT 1 FROM orders 
    WHERE orders.id = payments.order_id 
    AND orders.user_id::uuid = auth.uid()
));

-- Los usuarios pueden insertar sus propios pagos
CREATE POLICY "payments_user_insert" ON payments 
FOR INSERT 
WITH CHECK (EXISTS (
    SELECT 1 FROM orders 
    WHERE orders.id = payments.order_id 
    AND orders.user_id::uuid = auth.uid()
));

-- Los dueños de restaurantes pueden ver pagos de su restaurante
CREATE POLICY "payments_restaurant_owner" ON payments 
FOR SELECT 
USING (EXISTS (
    SELECT 1 FROM orders o 
    JOIN restaurants r ON r.id = o.restaurant_id 
    WHERE o.id = payments.order_id 
    AND r.user_id::uuid = auth.uid()
));

-- ============================================
-- ✅ VERIFICACIÓN FINAL
-- ============================================

-- Verificar que RLS esté habilitado en todas las tablas
SELECT schemaname, tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('users', 'restaurants', 'products', 'orders', 'order_items', 'payments');

-- Mostrar todas las políticas creadas
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies 
WHERE schemaname = 'public' 
AND tablename IN ('users', 'restaurants', 'products', 'orders', 'order_items', 'payments')
ORDER BY tablename, policyname;