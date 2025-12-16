-- ============================================
-- 🚀 POLÍTICAS RLS - AJUSTADAS AL SCHEMA REAL
-- ============================================

-- 🏪 RESTAURANTS TABLE
-- Política de lectura: Todos ven restaurantes aprobados + propietarios ven el suyo
CREATE POLICY "restaurants_read" ON restaurants FOR SELECT 
USING (status = 'approved' OR user_id = auth.uid());

-- Política de inserción: Solo usuarios con rol 'restaurante'
CREATE POLICY "restaurants_insert" ON restaurants FOR INSERT 
WITH CHECK (
    auth.uid() = user_id AND 
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'restaurante')
);

-- Política de actualización: Solo el propietario puede actualizar
CREATE POLICY "restaurants_update" ON restaurants FOR UPDATE 
USING (user_id = auth.uid());

-- 🍕 PRODUCTS TABLE
-- Política de lectura: Todos ven productos de restaurantes aprobados
CREATE POLICY "products_read" ON products FOR SELECT 
USING (
    EXISTS (
        SELECT 1 FROM restaurants 
        WHERE restaurants.id = products.restaurant_id 
        AND restaurants.status = 'approved'
    )
    OR 
    EXISTS (
        SELECT 1 FROM restaurants 
        WHERE restaurants.id = products.restaurant_id 
        AND restaurants.user_id = auth.uid()
    )
);

-- Política de inserción: Solo propietario del restaurante
CREATE POLICY "products_insert" ON products FOR INSERT 
WITH CHECK (
    EXISTS (
        SELECT 1 FROM restaurants 
        WHERE restaurants.id = restaurant_id 
        AND restaurants.user_id = auth.uid()
    )
);

-- Política de actualización: Solo propietario del restaurante
CREATE POLICY "products_update" ON products FOR UPDATE 
USING (
    EXISTS (
        SELECT 1 FROM restaurants 
        WHERE restaurants.id = products.restaurant_id 
        AND restaurants.user_id = auth.uid()
    )
);

-- Política de eliminación: Solo propietario del restaurante
CREATE POLICY "products_delete" ON products FOR DELETE 
USING (
    EXISTS (
        SELECT 1 FROM restaurants 
        WHERE restaurants.id = products.restaurant_id 
        AND restaurants.user_id = auth.uid()
    )
);

-- 📦 ORDERS TABLE
-- Política de lectura: Cliente, repartidor asignado, o restaurante
CREATE POLICY "orders_read" ON orders FOR SELECT 
USING (
    user_id = auth.uid() OR 
    delivery_agent_id = auth.uid() OR 
    EXISTS (
        SELECT 1 FROM restaurants 
        WHERE restaurants.id = orders.restaurant_id 
        AND restaurants.user_id = auth.uid()
    )
);

-- Política de inserción: Solo el cliente puede crear su pedido
CREATE POLICY "orders_insert" ON orders FOR INSERT 
WITH CHECK (
    auth.uid() = user_id AND 
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'cliente')
);

-- Política de actualización: Cliente, repartidor o restaurante según contexto
CREATE POLICY "orders_update" ON orders FOR UPDATE 
USING (
    user_id = auth.uid() OR 
    delivery_agent_id = auth.uid() OR 
    EXISTS (
        SELECT 1 FROM restaurants 
        WHERE restaurants.id = orders.restaurant_id 
        AND restaurants.user_id = auth.uid()
    )
);

-- 🛍️ ORDER_ITEMS TABLE
-- Política de lectura: A través de la orden
CREATE POLICY "order_items_read" ON order_items FOR SELECT 
USING (
    EXISTS (
        SELECT 1 FROM orders 
        WHERE orders.id = order_items.order_id 
        AND (
            orders.user_id = auth.uid() OR 
            orders.delivery_agent_id = auth.uid() OR 
            EXISTS (
                SELECT 1 FROM restaurants 
                WHERE restaurants.id = orders.restaurant_id 
                AND restaurants.user_id = auth.uid()
            )
        )
    )
);

-- Política de inserción: Solo al crear items de tu propia orden
CREATE POLICY "order_items_insert" ON order_items FOR INSERT 
WITH CHECK (
    EXISTS (
        SELECT 1 FROM orders 
        WHERE orders.id = order_id 
        AND orders.user_id = auth.uid()
    )
);

-- Política de actualización: Solo items de tu propia orden
CREATE POLICY "order_items_update" ON order_items FOR UPDATE 
USING (
    EXISTS (
        SELECT 1 FROM orders 
        WHERE orders.id = order_items.order_id 
        AND orders.user_id = auth.uid()
    )
);

-- Política de eliminación: Solo items de tu propia orden
CREATE POLICY "order_items_delete" ON order_items FOR DELETE 
USING (
    EXISTS (
        SELECT 1 FROM orders 
        WHERE orders.id = order_items.order_id 
        AND orders.user_id = auth.uid()
    )
);

-- 💳 PAYMENTS TABLE
-- Política de lectura: Solo el cliente de la orden
CREATE POLICY "payments_read" ON payments FOR SELECT 
USING (
    EXISTS (
        SELECT 1 FROM orders 
        WHERE orders.id = payments.order_id 
        AND orders.user_id = auth.uid()
    )
    OR 
    EXISTS (
        SELECT 1 FROM orders 
        WHERE orders.id = payments.order_id 
        AND EXISTS (
            SELECT 1 FROM restaurants 
            WHERE restaurants.id = orders.restaurant_id 
            AND restaurants.user_id = auth.uid()
        )
    )
);

-- Política de inserción: Solo para órdenes propias
CREATE POLICY "payments_insert" ON payments FOR INSERT 
WITH CHECK (
    EXISTS (
        SELECT 1 FROM orders 
        WHERE orders.id = order_id 
        AND orders.user_id = auth.uid()
    )
);

-- Política de actualización: Solo tus propios pagos
CREATE POLICY "payments_update" ON payments FOR UPDATE 
USING (
    EXISTS (
        SELECT 1 FROM orders 
        WHERE orders.id = payments.order_id 
        AND orders.user_id = auth.uid()
    )
);

-- ✅ VERIFICAR POLÍTICAS CREADAS
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