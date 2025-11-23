-- 🚀 POLÍTICAS CORREGIDAS - NOMBRES DE COLUMNAS EXACTOS
-- Ejecutar todo de una vez

-- Eliminar políticas existentes
DROP POLICY IF EXISTS "users_read" ON users;
DROP POLICY IF EXISTS "users_insert" ON users;
DROP POLICY IF EXISTS "users_update" ON users;
DROP POLICY IF EXISTS "restaurants_read" ON restaurants;
DROP POLICY IF EXISTS "restaurants_crud" ON restaurants;
DROP POLICY IF EXISTS "orders_read" ON orders;
DROP POLICY IF EXISTS "orders_crud" ON orders;
DROP POLICY IF EXISTS "order_items_read" ON order_items;

-- ✅ USERS - Políticas esenciales
CREATE POLICY "users_read" ON users
FOR SELECT USING (auth.uid() = id);

CREATE POLICY "users_insert" ON users
FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "users_update" ON users
FOR UPDATE USING (auth.uid() = id);

-- ✅ RESTAURANTS - Usar user_id (no owner_id)
CREATE POLICY "restaurants_read" ON restaurants
FOR SELECT USING (true); -- Todos pueden ver restaurantes

CREATE POLICY "restaurants_crud" ON restaurants
FOR ALL USING (auth.uid() = user_id); -- Solo el dueño puede modificar

-- ✅ ORDERS - Acceso a tus propias órdenes
CREATE POLICY "orders_read" ON orders
FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "orders_crud" ON orders
FOR ALL USING (auth.uid() = user_id);

-- ✅ ORDER_ITEMS - Acceso vía orden
CREATE POLICY "order_items_read" ON order_items
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM orders 
    WHERE orders.id = order_items.order_id 
    AND orders.user_id = auth.uid()
  )
);

-- 📊 Verificar políticas creadas
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