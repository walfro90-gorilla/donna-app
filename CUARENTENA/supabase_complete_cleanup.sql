-- 🧹 LIMPIEZA TOTAL DE POLÍTICAS RLS
-- Este script elimina TODAS las políticas existentes y las recrea desde cero

-- ============================
-- 🔥 PASO 1: ELIMINAR TODAS LAS POLÍTICAS EXISTENTES
-- ============================

-- Eliminar políticas de USERS
DROP POLICY IF EXISTS "users_own_profile_read" ON users;
DROP POLICY IF EXISTS "users_own_profile_write" ON users;
DROP POLICY IF EXISTS "users_select_own" ON users;
DROP POLICY IF EXISTS "users_update_own" ON users;
DROP POLICY IF EXISTS "users_insert_own" ON users;

-- Eliminar políticas de RESTAURANTS
DROP POLICY IF EXISTS "restaurants_public_read" ON restaurants;
DROP POLICY IF EXISTS "restaurants_owner_write" ON restaurants;
DROP POLICY IF EXISTS "restaurants_select_all" ON restaurants;
DROP POLICY IF EXISTS "restaurants_update_owner" ON restaurants;
DROP POLICY IF EXISTS "restaurants_insert_owner" ON restaurants;

-- Eliminar políticas de ORDERS
DROP POLICY IF EXISTS "orders_own_read" ON orders;
DROP POLICY IF EXISTS "orders_own_write" ON orders;
DROP POLICY IF EXISTS "orders_select_own" ON orders;
DROP POLICY IF EXISTS "orders_update_own" ON orders;
DROP POLICY IF EXISTS "orders_insert_own" ON orders;

-- Eliminar políticas de ORDER_ITEMS
DROP POLICY IF EXISTS "order_items_own_read" ON order_items;
DROP POLICY IF EXISTS "order_items_own_write" ON order_items;
DROP POLICY IF EXISTS "order_items_select_own" ON order_items;
DROP POLICY IF EXISTS "order_items_update_own" ON order_items;
DROP POLICY IF EXISTS "order_items_insert_own" ON order_items;

-- ============================
-- 🔒 PASO 2: DESHABILITAR RLS TEMPORALMENTE
-- ============================

ALTER TABLE users DISABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants DISABLE ROW LEVEL SECURITY;
ALTER TABLE orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE order_items DISABLE ROW LEVEL SECURITY;

-- ============================
-- ✅ PASO 3: CREAR POLÍTICAS ULTRA-SIMPLES
-- ============================

-- 🔐 USERS: Solo su propio perfil
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_read_own" ON users
    FOR SELECT USING (auth.uid()::text = id::text);

CREATE POLICY "users_write_own" ON users
    FOR ALL USING (auth.uid()::text = id::text);

-- 🍽️ RESTAURANTS: Público para lectura
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "restaurants_read_all" ON restaurants
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "restaurants_write_owner" ON restaurants
    FOR ALL TO authenticated USING (auth.uid()::text = owner_id::text);

-- 📦 ORDERS: Solo sus propias órdenes
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "orders_read_own" ON orders
    FOR SELECT TO authenticated USING (auth.uid()::text = user_id::text);

CREATE POLICY "orders_write_own" ON orders
    FOR ALL TO authenticated USING (auth.uid()::text = user_id::text);

-- 🍕 ORDER_ITEMS: Solo items de sus órdenes
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "order_items_read_own" ON order_items
    FOR SELECT TO authenticated USING (
        EXISTS (
            SELECT 1 FROM orders 
            WHERE orders.id::text = order_items.order_id::text 
            AND orders.user_id::text = auth.uid()::text
        )
    );

CREATE POLICY "order_items_write_own" ON order_items
    FOR ALL TO authenticated USING (
        EXISTS (
            SELECT 1 FROM orders 
            WHERE orders.id::text = order_items.order_id::text 
            AND orders.user_id::text = auth.uid()::text
        )
    );

-- ============================
-- 🎯 CONFIRMACIÓN
-- ============================

SELECT 'POLÍTICAS RLS RECREADAS EXITOSAMENTE' AS status;