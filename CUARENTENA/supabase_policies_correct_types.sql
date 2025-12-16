-- ============================================
-- POLÍTICAS RLS CON TIPOS CORRECTOS
-- users.id = uuid (sin cast)
-- restaurants.user_id = text (con cast)
-- orders.user_id = text (con cast)
-- ============================================

-- 📋 POLÍTICAS PARA USERS (uuid = uuid)
CREATE POLICY "users_select" ON users
    FOR SELECT USING (id = auth.uid());

CREATE POLICY "users_insert" ON users
    FOR INSERT WITH CHECK (id = auth.uid());

CREATE POLICY "users_update" ON users
    FOR UPDATE USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- 🍽️ POLÍTICAS PARA RESTAURANTS (text = uuid::text)
CREATE POLICY "restaurants_select" ON restaurants
    FOR SELECT USING (user_id = auth.uid()::text);

CREATE POLICY "restaurants_insert" ON restaurants
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);

CREATE POLICY "restaurants_update" ON restaurants
    FOR UPDATE USING (user_id = auth.uid()::text)
    WITH CHECK (user_id = auth.uid()::text);

-- 📦 POLÍTICAS PARA ORDERS (text = uuid::text)
CREATE POLICY "orders_select" ON orders
    FOR SELECT USING (user_id = auth.uid()::text);

CREATE POLICY "orders_insert" ON orders
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);

CREATE POLICY "orders_update" ON orders
    FOR UPDATE USING (user_id = auth.uid()::text)
    WITH CHECK (user_id = auth.uid()::text);

-- 🛒 POLÍTICAS PARA ORDER_ITEMS (acceso vía orders.user_id)
CREATE POLICY "order_items_select" ON order_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM orders 
            WHERE orders.id = order_items.order_id 
            AND orders.user_id = auth.uid()::text
        )
    );

CREATE POLICY "order_items_insert" ON order_items
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM orders 
            WHERE orders.id = order_items.order_id 
            AND orders.user_id = auth.uid()::text
        )
    );

CREATE POLICY "order_items_update" ON order_items
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM orders 
            WHERE orders.id = order_items.order_id 
            AND orders.user_id = auth.uid()::text
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM orders 
            WHERE orders.id = order_items.order_id 
            AND orders.user_id = auth.uid()::text
        )
    );

-- ✅ VERIFICAR POLÍTICAS CREADAS
SELECT 
    schemaname,
    tablename, 
    policyname,
    cmd,
    roles
FROM pg_policies 
WHERE schemaname = 'public'
ORDER BY tablename, policyname;