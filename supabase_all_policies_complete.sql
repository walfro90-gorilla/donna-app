-- =================================================================
-- 🚀 POLÍTICAS RLS COMPLETAS PARA DOA REPARTOS
-- =================================================================
-- Basado en la estructura exacta de las tablas con tipos UUID

-- Limpiar políticas existentes (excepto users que ya funciona)
DROP POLICY IF EXISTS "restaurants_read" ON restaurants;
DROP POLICY IF EXISTS "restaurants_insert" ON restaurants;
DROP POLICY IF EXISTS "restaurants_update" ON restaurants;
DROP POLICY IF EXISTS "restaurants_delete" ON restaurants;

DROP POLICY IF EXISTS "products_read" ON products;
DROP POLICY IF EXISTS "products_insert" ON products;
DROP POLICY IF EXISTS "products_update" ON products;
DROP POLICY IF EXISTS "products_delete" ON products;

DROP POLICY IF EXISTS "orders_read" ON orders;
DROP POLICY IF EXISTS "orders_insert" ON orders;
DROP POLICY IF EXISTS "orders_update" ON orders;
DROP POLICY IF EXISTS "orders_delete" ON orders;

DROP POLICY IF EXISTS "order_items_read" ON order_items;
DROP POLICY IF EXISTS "order_items_insert" ON order_items;
DROP POLICY IF EXISTS "order_items_update" ON order_items;
DROP POLICY IF EXISTS "order_items_delete" ON order_items;

DROP POLICY IF EXISTS "payments_read" ON payments;
DROP POLICY IF EXISTS "payments_insert" ON payments;
DROP POLICY IF EXISTS "payments_update" ON payments;

-- =================================================================
-- 🏪 POLÍTICAS PARA RESTAURANTS
-- =================================================================

-- Leer: todos pueden ver restaurantes aprobados, propietario ve el suyo
CREATE POLICY "restaurants_read" ON restaurants
  FOR SELECT
  USING (
    status = 'approved' OR 
    user_id = auth.uid()
  );

-- Insertar: usuarios con rol 'restaurante' pueden crear su restaurante
CREATE POLICY "restaurants_insert" ON restaurants
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id AND
    EXISTS (
      SELECT 1 FROM users 
      WHERE id = auth.uid() 
      AND role = 'restaurante'
    )
  );

-- Actualizar: solo el propietario puede actualizar su restaurante
CREATE POLICY "restaurants_update" ON restaurants
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- =================================================================
-- 🍕 POLÍTICAS PARA PRODUCTS
-- =================================================================

-- Leer: todos pueden ver productos de restaurantes aprobados
CREATE POLICY "products_read" ON products
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM restaurants r
      WHERE r.id = products.restaurant_id
      AND (r.status = 'approved' OR r.user_id = auth.uid())
    )
  );

-- Insertar: propietario del restaurante puede agregar productos
CREATE POLICY "products_insert" ON products
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM restaurants r
      WHERE r.id = restaurant_id
      AND r.user_id = auth.uid()
    )
  );

-- Actualizar: propietario del restaurante puede actualizar productos
CREATE POLICY "products_update" ON products
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM restaurants r
      WHERE r.id = products.restaurant_id
      AND r.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM restaurants r
      WHERE r.id = restaurant_id
      AND r.user_id = auth.uid()
    )
  );

-- Eliminar: propietario del restaurante puede eliminar productos
CREATE POLICY "products_delete" ON products
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM restaurants r
      WHERE r.id = products.restaurant_id
      AND r.user_id = auth.uid()
    )
  );

-- =================================================================
-- 📦 POLÍTICAS PARA ORDERS
-- =================================================================

-- Leer: cliente ve sus pedidos, restaurante ve pedidos de sus productos, repartidor ve los asignados
CREATE POLICY "orders_read" ON orders
  FOR SELECT
  USING (
    user_id = auth.uid() OR  -- Cliente que hizo el pedido
    delivery_agent_id = auth.uid() OR  -- Repartidor asignado
    EXISTS (
      SELECT 1 FROM restaurants r
      WHERE r.id = orders.restaurant_id
      AND r.user_id = auth.uid()  -- Propietario del restaurante
    )
  );

-- Insertar: cualquier usuario autenticado puede crear pedidos
CREATE POLICY "orders_insert" ON orders
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Actualizar: cliente, restaurante o repartidor pueden actualizar según su rol
CREATE POLICY "orders_update" ON orders
  FOR UPDATE
  USING (
    user_id = auth.uid() OR  -- Cliente
    delivery_agent_id = auth.uid() OR  -- Repartidor
    EXISTS (
      SELECT 1 FROM restaurants r
      WHERE r.id = orders.restaurant_id
      AND r.user_id = auth.uid()  -- Restaurante
    )
  )
  WITH CHECK (
    user_id = auth.uid() OR
    delivery_agent_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM restaurants r
      WHERE r.id = restaurant_id
      AND r.user_id = auth.uid()
    )
  );

-- =================================================================
-- 🛒 POLÍTICAS PARA ORDER_ITEMS
-- =================================================================

-- Leer: si puedes ver el pedido, puedes ver sus items
CREATE POLICY "order_items_read" ON order_items
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = order_items.order_id
      AND (
        o.user_id = auth.uid() OR
        o.delivery_agent_id = auth.uid() OR
        EXISTS (
          SELECT 1 FROM restaurants r
          WHERE r.id = o.restaurant_id
          AND r.user_id = auth.uid()
        )
      )
    )
  );

-- Insertar: solo al crear el pedido (el cliente propietario del pedido)
CREATE POLICY "order_items_insert" ON order_items
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = order_id
      AND o.user_id = auth.uid()
    )
  );

-- Actualizar: solo el cliente propietario del pedido puede modificar items
CREATE POLICY "order_items_update" ON order_items
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = order_items.order_id
      AND o.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = order_id
      AND o.user_id = auth.uid()
    )
  );

-- =================================================================
-- 💳 POLÍTICAS PARA PAYMENTS
-- =================================================================

-- Leer: solo quien puede ver el pedido puede ver el pago
CREATE POLICY "payments_read" ON payments
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = payments.order_id
      AND (
        o.user_id = auth.uid() OR
        EXISTS (
          SELECT 1 FROM restaurants r
          WHERE r.id = o.restaurant_id
          AND r.user_id = auth.uid()
        )
      )
    )
  );

-- Insertar: solo el cliente propietario del pedido
CREATE POLICY "payments_insert" ON payments
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = order_id
      AND o.user_id = auth.uid()
    )
  );

-- Actualizar: solo el cliente propietario del pedido
CREATE POLICY "payments_update" ON payments
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = payments.order_id
      AND o.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = order_id
      AND o.user_id = auth.uid()
    )
  );

-- =================================================================
-- ✅ VERIFICAR POLÍTICAS CREADAS
-- =================================================================
SELECT 
  schemaname,
  tablename,
  policyname,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE schemaname = 'public'
ORDER BY tablename, policyname;