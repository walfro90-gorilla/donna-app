-- ===================================================
-- SOLUCIÓN DEFINITIVA: ELIMINAR RECURSIÓN INFINITA
-- ===================================================

-- 🔥 PASO 1: DESHABILITAR RLS Y ELIMINAR TODAS LAS POLÍTICAS
ALTER TABLE public.users DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items DISABLE ROW LEVEL SECURITY;

-- 🗑️ PASO 2: ELIMINAR TODAS LAS POLÍTICAS EXISTENTES
DROP POLICY IF EXISTS "users_select_policy" ON public.users;
DROP POLICY IF EXISTS "users_insert_policy" ON public.users;
DROP POLICY IF EXISTS "users_update_policy" ON public.users;
DROP POLICY IF EXISTS "users_delete_policy" ON public.users;

DROP POLICY IF EXISTS "restaurants_select_policy" ON public.restaurants;
DROP POLICY IF EXISTS "restaurants_insert_policy" ON public.restaurants;
DROP POLICY IF EXISTS "restaurants_update_policy" ON public.restaurants;
DROP POLICY IF EXISTS "restaurants_delete_policy" ON public.restaurants;

DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_insert_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_delete_policy" ON public.orders;

DROP POLICY IF EXISTS "order_items_select_policy" ON public.order_items;
DROP POLICY IF EXISTS "order_items_insert_policy" ON public.order_items;
DROP POLICY IF EXISTS "order_items_update_policy" ON public.order_items;
DROP POLICY IF EXISTS "order_items_delete_policy" ON public.order_items;

-- 🔓 PASO 3: POLÍTICAS SUPER SIMPLES SIN RECURSIÓN

-- ✅ USERS: Solo acceso propio
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_data" ON public.users
FOR ALL 
TO authenticated
USING (id::uuid = auth.uid())
WITH CHECK (id::uuid = auth.uid());

-- ✅ RESTAURANTS: Lectura pública, edición propia
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "restaurants_public_read" ON public.restaurants
FOR SELECT 
TO authenticated
USING (true);

CREATE POLICY "restaurants_own_write" ON public.restaurants
FOR ALL 
TO authenticated
USING (user_id::uuid = auth.uid())
WITH CHECK (user_id::uuid = auth.uid());

-- ✅ ORDERS: Solo acceso propio
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "orders_own_data" ON public.orders
FOR ALL 
TO authenticated
USING (user_id::uuid = auth.uid())
WITH CHECK (user_id::uuid = auth.uid());

-- ✅ ORDER_ITEMS: Solo acceso propio vía order
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "order_items_via_order" ON public.order_items
FOR ALL 
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.orders 
    WHERE orders.id = order_items.order_id 
    AND orders.user_id::uuid = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.orders 
    WHERE orders.id = order_items.order_id 
    AND orders.user_id::uuid = auth.uid()
  )
);

-- ✅ CONFIRMAR CONFIGURACIÓN
SELECT 
  schemaname,
  tablename,
  rowsecurity,
  policies
FROM pg_tables t
LEFT JOIN (
  SELECT 
    schemaname as pol_schema,
    tablename as pol_table,
    count(*) as policies
  FROM pg_policies 
  GROUP BY schemaname, tablename
) p ON t.schemaname = p.pol_schema AND t.tablename = p.pol_table
WHERE t.schemaname = 'public' 
AND t.tablename IN ('users', 'restaurants', 'orders', 'order_items')
ORDER BY t.tablename;