-- 🚀 POLÍTICAS RLS CON CAST CORRECTO PARA DOA REPARTOS
-- Soluciona el error: operator does not exist: text = uuid

-- ===== TABLA USERS =====
-- Política para leer tu propio perfil
CREATE POLICY "users_read" ON users
FOR SELECT
TO authenticated
USING (id = auth.uid());

-- Política para insertar tu propio perfil (CRÍTICA)
CREATE POLICY "users_insert" ON users
FOR INSERT
TO authenticated
WITH CHECK (id = auth.uid());

-- Política para actualizar tu propio perfil
CREATE POLICY "users_update" ON users
FOR UPDATE
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- ===== TABLA RESTAURANTS =====
-- Política para leer todos los restaurantes (público)
CREATE POLICY "restaurants_read_all" ON restaurants
FOR SELECT
TO authenticated
USING (true);

-- Política para que cada usuario maneje solo sus restaurantes
CREATE POLICY "restaurants_owner_access" ON restaurants
FOR ALL
TO authenticated
USING (user_id = auth.uid()::text)
WITH CHECK (user_id = auth.uid()::text);

-- ===== TABLA ORDERS =====
-- Política para leer todas las órdenes (restaurantes ven todas, usuarios ven las suyas)
CREATE POLICY "orders_read" ON orders
FOR SELECT
TO authenticated
USING (
    user_id = auth.uid()::text OR 
    restaurant_id IN (
        SELECT id FROM restaurants WHERE user_id = auth.uid()::text
    )
);

-- Política para insertar órdenes (solo el usuario puede crear sus propias órdenes)
CREATE POLICY "orders_insert" ON orders
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid()::text);

-- Política para actualizar órdenes
CREATE POLICY "orders_update" ON orders
FOR UPDATE
TO authenticated
USING (
    user_id = auth.uid()::text OR 
    restaurant_id IN (
        SELECT id FROM restaurants WHERE user_id = auth.uid()::text
    )
)
WITH CHECK (
    user_id = auth.uid()::text OR 
    restaurant_id IN (
        SELECT id FROM restaurants WHERE user_id = auth.uid()::text
    )
);

-- ===== TABLA ORDER_ITEMS =====
-- Política para leer items de órdenes (via órdenes del usuario)
CREATE POLICY "order_items_read" ON order_items
FOR SELECT
TO authenticated
USING (
    order_id IN (
        SELECT id FROM orders WHERE 
        user_id = auth.uid()::text OR 
        restaurant_id IN (
            SELECT id FROM restaurants WHERE user_id = auth.uid()::text
        )
    )
);

-- Política para insertar items de órdenes
CREATE POLICY "order_items_insert" ON order_items
FOR INSERT
TO authenticated
WITH CHECK (
    order_id IN (
        SELECT id FROM orders WHERE user_id = auth.uid()::text
    )
);

-- Política para actualizar items de órdenes
CREATE POLICY "order_items_update" ON order_items
FOR UPDATE
TO authenticated
USING (
    order_id IN (
        SELECT id FROM orders WHERE 
        user_id = auth.uid()::text OR 
        restaurant_id IN (
            SELECT id FROM restaurants WHERE user_id = auth.uid()::text
        )
    )
)
WITH CHECK (
    order_id IN (
        SELECT id FROM orders WHERE 
        user_id = auth.uid()::text OR 
        restaurant_id IN (
            SELECT id FROM restaurants WHERE user_id = auth.uid()::text
        )
    )
);

-- ===== HABILITAR RLS EN TODAS LAS TABLAS =====
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

-- ===== VERIFICAR POLÍTICAS CREADAS =====
SELECT 
    schemaname, 
    tablename, 
    policyname, 
    cmd,
    roles
FROM pg_policies 
WHERE schemaname = 'public' 
ORDER BY tablename, policyname;