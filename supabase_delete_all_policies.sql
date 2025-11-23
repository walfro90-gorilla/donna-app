-- 🧹 ELIMINAR TODAS LAS POLÍTICAS EXISTENTES

-- Deshabilitar RLS temporalmente
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants DISABLE ROW LEVEL SECURITY;
ALTER TABLE orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE order_items DISABLE ROW LEVEL SECURITY;

-- Eliminar todas las políticas de users
DROP POLICY IF EXISTS "users_own_profile" ON users;
DROP POLICY IF EXISTS "users_read_own" ON users;
DROP POLICY IF EXISTS "users_update_own" ON users;
DROP POLICY IF EXISTS "users_insert_own" ON users;
DROP POLICY IF EXISTS "users_public_read" ON users;
DROP POLICY IF EXISTS "users_owner_write" ON users;

-- Eliminar todas las políticas de restaurants
DROP POLICY IF EXISTS "restaurants_public_read" ON restaurants;
DROP POLICY IF EXISTS "restaurants_owner_write" ON restaurants;
DROP POLICY IF EXISTS "restaurants_read_all" ON restaurants;
DROP POLICY IF EXISTS "restaurants_owner_update" ON restaurants;

-- Eliminar todas las políticas de orders
DROP POLICY IF EXISTS "orders_own_read" ON orders;
DROP POLICY IF EXISTS "orders_own_write" ON orders;
DROP POLICY IF EXISTS "orders_user_read" ON orders;
DROP POLICY IF EXISTS "orders_user_write" ON orders;

-- Eliminar todas las políticas de order_items
DROP POLICY IF EXISTS "order_items_own_read" ON order_items;
DROP POLICY IF EXISTS "order_items_own_write" ON order_items;
DROP POLICY IF EXISTS "order_items_user_read" ON order_items;
DROP POLICY IF EXISTS "order_items_user_write" ON order_items;

-- Verificar que no quedan políticas
SELECT 
    schemaname,
    tablename,
    policyname,
    cmd,
    qual
FROM pg_policies 
WHERE schemaname = 'public'
ORDER BY tablename, policyname;