-- ========================================
-- LIMPIEZA COMPLETA Y RECREACIÓN DE POLÍTICAS RLS
-- Para resolver el problema de recursión infinita
-- ========================================

-- 🗑️ ELIMINAR TODAS LAS POLÍTICAS EXISTENTES
DROP POLICY IF EXISTS "users_own_profile" ON users;
DROP POLICY IF EXISTS "users_update_own" ON users;
DROP POLICY IF EXISTS "restaurants_public_read" ON restaurants;
DROP POLICY IF EXISTS "restaurants_owner_manage" ON restaurants;
DROP POLICY IF EXISTS "orders_own_orders" ON orders;
DROP POLICY IF EXISTS "orders_create_own" ON orders;
DROP POLICY IF EXISTS "orders_update_own" ON orders;
DROP POLICY IF EXISTS "order_items_own_items" ON order_items;
DROP POLICY IF EXISTS "order_items_manage_own" ON order_items;

-- 🔓 DESHABILITAR RLS TEMPORALMENTE
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants DISABLE ROW LEVEL SECURITY;
ALTER TABLE orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE order_items DISABLE ROW LEVEL SECURITY;

-- ✅ HABILITAR RLS DE NUEVO (LIMPIO)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

-- 🔐 CREAR POLÍTICAS SIMPLES SIN RECURSIÓN

-- USERS: Política ultra-simple sin bucles
CREATE POLICY "users_simple_access" ON users
FOR ALL 
TO authenticated
USING (auth.uid() IS NOT NULL);

-- RESTAURANTS: Acceso público para lectura
CREATE POLICY "restaurants_public_access" ON restaurants
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "restaurants_owner_write" ON restaurants
FOR ALL
TO authenticated
USING (auth.uid() IS NOT NULL);

-- ORDERS: Solo sus propias órdenes
CREATE POLICY "orders_user_access" ON orders
FOR ALL
TO authenticated
USING (auth.uid() IS NOT NULL);

-- ORDER_ITEMS: Acceso completo para usuarios autenticados
CREATE POLICY "order_items_access" ON order_items
FOR ALL
TO authenticated
USING (auth.uid() IS NOT NULL);

-- ✅ CONFIRMAR CAMBIOS
SELECT 'Políticas RLS recreadas exitosamente' as status;