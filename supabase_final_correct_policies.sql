-- 🔧 ELIMINAR TODAS LAS POLÍTICAS Y RECREAR CON SCHEMA REAL
-- Basado en la estructura exacta mostrada en el screenshot

-- 1️⃣ ELIMINAR TODAS LAS POLÍTICAS EXISTENTES
DROP POLICY IF EXISTS "users_own_profile" ON users;
DROP POLICY IF EXISTS "users_insert_own" ON users;
DROP POLICY IF EXISTS "users_update_own" ON users;
DROP POLICY IF EXISTS "restaurants_public_read" ON restaurants;
DROP POLICY IF EXISTS "restaurants_owner_write" ON restaurants;
DROP POLICY IF EXISTS "orders_own_read" ON orders;
DROP POLICY IF EXISTS "orders_insert_own" ON orders;
DROP POLICY IF EXISTS "order_items_own_read" ON order_items;

-- 2️⃣ DESHABILITAR RLS TEMPORALMENTE
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants DISABLE ROW LEVEL SECURITY;
ALTER TABLE orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE order_items DISABLE ROW LEVEL SECURITY;

-- 3️⃣ RECREAR POLÍTICAS CORRECTAS USANDO LA ESTRUCTURA REAL

-- TABLA USERS (columna: id uuid)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_read_own_profile" ON users
    FOR SELECT 
    USING (id = auth.uid());

CREATE POLICY "users_insert_own_profile" ON users
    FOR INSERT 
    WITH CHECK (id = auth.uid());

CREATE POLICY "users_update_own_profile" ON users
    FOR UPDATE 
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- TABLA RESTAURANTS (columna: user_id text)
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "restaurants_public_read" ON restaurants
    FOR SELECT 
    TO authenticated
    USING (true);

CREATE POLICY "restaurants_owner_manage" ON restaurants
    FOR ALL 
    USING (user_id::uuid = auth.uid())
    WITH CHECK (user_id::uuid = auth.uid());

-- TABLA ORDERS (columna: user_id text)
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "orders_own_access" ON orders
    FOR ALL 
    USING (user_id::uuid = auth.uid())
    WITH CHECK (user_id::uuid = auth.uid());

-- TABLA ORDER_ITEMS (acceso a través de orders.user_id)
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "order_items_own_access" ON order_items
    FOR ALL 
    USING (
        EXISTS (
            SELECT 1 FROM orders 
            WHERE orders.id = order_items.order_id 
            AND orders.user_id::uuid = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM orders 
            WHERE orders.id = order_items.order_id 
            AND orders.user_id::uuid = auth.uid()
        )
    );

-- 4️⃣ VERIFICAR TABLAS Y POLÍTICAS CREADAS
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    cmd,
    roles
FROM pg_policies 
WHERE schemaname = 'public'
ORDER BY tablename, policyname;