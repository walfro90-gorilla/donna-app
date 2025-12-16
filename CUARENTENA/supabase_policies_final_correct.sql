-- ========================================
-- 🚀 POLÍTICAS RLS FINALES - TIPOS CORRECTOS
-- ========================================

-- 🔧 Eliminar todas las políticas existentes (por si acaso)
DROP POLICY IF EXISTS "users_read" ON users;
DROP POLICY IF EXISTS "users_write" ON users; 
DROP POLICY IF EXISTS "users_insert" ON users;
DROP POLICY IF EXISTS "restaurants_read" ON restaurants;
DROP POLICY IF EXISTS "restaurants_write" ON restaurants;
DROP POLICY IF EXISTS "orders_read" ON orders;
DROP POLICY IF EXISTS "orders_write" ON orders;
DROP POLICY IF EXISTS "order_items_read" ON order_items;

-- ========================================
-- 👤 TABLA: users
-- ========================================
CREATE POLICY "users_read" ON users
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "users_write" ON users  
    FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "users_insert" ON users
    FOR INSERT WITH CHECK (auth.uid() = id);

-- ========================================
-- 🏪 TABLA: restaurants  
-- ========================================
CREATE POLICY "restaurants_read" ON restaurants
    FOR SELECT USING (true);

CREATE POLICY "restaurants_write" ON restaurants
    FOR ALL USING (auth.uid() = owner_id);

-- ========================================
-- 📦 TABLA: orders
-- ========================================
CREATE POLICY "orders_read" ON orders
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "orders_write" ON orders
    FOR ALL USING (auth.uid() = user_id);

-- ========================================
-- 📋 TABLA: order_items
-- ========================================
CREATE POLICY "order_items_read" ON order_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM orders 
            WHERE orders.id = order_items.order_id 
            AND orders.user_id = auth.uid()
        )
    );

CREATE POLICY "order_items_write" ON order_items
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM orders 
            WHERE orders.id = order_items.order_id 
            AND orders.user_id = auth.uid()
        )
    );

-- ========================================
-- 📊 VERIFICACIÓN FINAL
-- ========================================
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE schemaname = 'public'
ORDER BY tablename, policyname;