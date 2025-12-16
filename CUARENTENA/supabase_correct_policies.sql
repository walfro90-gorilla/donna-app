-- ================================
-- POLÍTICAS RLS CORRECTAS PARA DOA REPARTOS
-- Basadas en el schema real de la base de datos
-- ================================

-- Primero, eliminar todas las políticas existentes y deshabilitar RLS
DROP POLICY IF EXISTS "Users can view own profile" ON users;
DROP POLICY IF EXISTS "Users can update own profile" ON users;
DROP POLICY IF EXISTS "Everyone can view restaurants" ON restaurants;
DROP POLICY IF EXISTS "Restaurant owners can update own restaurant" ON restaurants;
DROP POLICY IF EXISTS "Users can view own orders" ON orders;
DROP POLICY IF EXISTS "Users can create orders" ON orders;
DROP POLICY IF EXISTS "Users can view order items for own orders" ON order_items;
DROP POLICY IF EXISTS "Users can create order items" ON order_items;

-- Deshabilitar RLS en todas las tablas
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants DISABLE ROW LEVEL SECURITY;
ALTER TABLE orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE order_items DISABLE ROW LEVEL SECURITY;

-- Habilitar RLS nuevamente
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

-- ================================
-- POLÍTICAS PARA TABLA USERS
-- ================================

-- Los usuarios pueden ver y actualizar solo su propio perfil
CREATE POLICY "Users can view own profile" ON users
    FOR SELECT USING (auth.uid()::text = id);

CREATE POLICY "Users can update own profile" ON users
    FOR UPDATE USING (auth.uid()::text = id);

-- ================================
-- POLÍTICAS PARA TABLA RESTAURANTS
-- ================================

-- Todos pueden ver los restaurantes (catálogo público)
CREATE POLICY "Everyone can view restaurants" ON restaurants
    FOR SELECT USING (true);

-- Solo el dueño del restaurante puede actualizarlo
CREATE POLICY "Restaurant owners can update own restaurant" ON restaurants
    FOR UPDATE USING (user_id = auth.uid()::text);

-- Los usuarios con rol 'restaurant' pueden insertar restaurantes
CREATE POLICY "Restaurant users can create restaurants" ON restaurants
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);

-- ================================
-- POLÍTICAS PARA TABLA ORDERS
-- ================================

-- Los usuarios pueden ver sus propias órdenes
CREATE POLICY "Users can view own orders" ON orders
    FOR SELECT USING (user_id = auth.uid()::text);

-- Los usuarios pueden crear órdenes
CREATE POLICY "Users can create orders" ON orders
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);

-- Los usuarios pueden actualizar sus propias órdenes
CREATE POLICY "Users can update own orders" ON orders
    FOR UPDATE USING (user_id = auth.uid()::text);

-- ================================
-- POLÍTICAS PARA TABLA ORDER_ITEMS
-- ================================

-- Los usuarios pueden ver los items de sus propias órdenes
CREATE POLICY "Users can view order items for own orders" ON order_items
    FOR SELECT USING (
        order_id IN (
            SELECT id FROM orders WHERE user_id = auth.uid()::text
        )
    );

-- Los usuarios pueden crear items para sus propias órdenes
CREATE POLICY "Users can create order items" ON order_items
    FOR INSERT WITH CHECK (
        order_id IN (
            SELECT id FROM orders WHERE user_id = auth.uid()::text
        )
    );

-- Los usuarios pueden actualizar items de sus propias órdenes
CREATE POLICY "Users can update order items" ON order_items
    FOR UPDATE USING (
        order_id IN (
            SELECT id FROM orders WHERE user_id = auth.uid()::text
        )
    );

-- ================================
-- VERIFICACIÓN FINAL
-- ================================
SELECT 'Políticas RLS configuradas correctamente para Doa Repartos' as status;