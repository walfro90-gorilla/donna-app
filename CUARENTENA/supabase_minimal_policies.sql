-- 🚀 POLÍTICAS MÍNIMAS NECESARIAS PARA QUE LA APP FUNCIONE
-- Solo las políticas esenciales para login, registro y navegación

-- ✅ TABLA USERS - Políticas básicas para perfil de usuario
-- Permitir leer tu propio perfil
CREATE POLICY "users_read_own" 
ON "public"."users" 
FOR SELECT 
USING (auth.uid()::text = id::text);

-- Permitir actualizar tu propio perfil
CREATE POLICY "users_update_own" 
ON "public"."users" 
FOR UPDATE 
USING (auth.uid()::text = id::text);

-- ⭐ CRÍTICO: Permitir INSERTAR tu propio perfil al registrarse
CREATE POLICY "users_insert_own" 
ON "public"."users" 
FOR INSERT 
WITH CHECK (auth.uid()::text = id::text);

-- ✅ TABLA RESTAURANTS - Políticas básicas
-- Todos pueden ver restaurantes públicos
CREATE POLICY "restaurants_public_read" 
ON "public"."restaurants" 
FOR SELECT 
USING (true);

-- Solo el dueño puede actualizar su restaurante
CREATE POLICY "restaurants_owner_update" 
ON "public"."restaurants" 
FOR UPDATE 
USING (auth.uid()::text = user_id);

-- Solo usuarios autenticados pueden crear restaurantes
CREATE POLICY "restaurants_insert_authenticated" 
ON "public"."restaurants" 
FOR INSERT 
WITH CHECK (auth.uid() IS NOT NULL AND auth.uid()::text = user_id);

-- ✅ TABLA ORDERS - Políticas básicas
-- Solo puedes ver tus propias órdenes
CREATE POLICY "orders_read_own" 
ON "public"."orders" 
FOR SELECT 
USING (auth.uid()::text = user_id);

-- Solo puedes crear órdenes para ti mismo
CREATE POLICY "orders_insert_own" 
ON "public"."orders" 
FOR INSERT 
WITH CHECK (auth.uid()::text = user_id);

-- Solo puedes actualizar tus propias órdenes
CREATE POLICY "orders_update_own" 
ON "public"."orders" 
FOR UPDATE 
USING (auth.uid()::text = user_id);

-- ✅ TABLA ORDER_ITEMS - Políticas básicas
-- Solo puedes ver items de tus órdenes
CREATE POLICY "order_items_read_own" 
ON "public"."order_items" 
FOR SELECT 
USING (EXISTS (
  SELECT 1 FROM orders 
  WHERE orders.id = order_items.order_id 
  AND orders.user_id = auth.uid()::text
));

-- Solo puedes insertar items en tus órdenes
CREATE POLICY "order_items_insert_own" 
ON "public"."order_items" 
FOR INSERT 
WITH CHECK (EXISTS (
  SELECT 1 FROM orders 
  WHERE orders.id = order_items.order_id 
  AND orders.user_id = auth.uid()::text
));

-- ✅ VERIFICACIÓN FINAL
SELECT 
  tablename,
  policyname,
  cmd,
  qual
FROM pg_policies 
WHERE tablename IN ('users', 'restaurants', 'orders', 'order_items')
ORDER BY tablename, policyname;