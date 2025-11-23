-- 🚨 OPCIÓN NUCLEAR: ELIMINAR TODO Y EMPEZAR DE CERO
-- Este script elimina TODAS las políticas y recrea desde cero SIN RECURSIÓN

-- 1️⃣ DESHABILITAR RLS EN TODAS LAS TABLAS
ALTER TABLE public.users DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items DISABLE ROW LEVEL SECURITY;

-- 2️⃣ ELIMINAR TODAS LAS POLÍTICAS EXISTENTES
DROP POLICY IF EXISTS "users_own_data" ON public.users;
DROP POLICY IF EXISTS "users_read_own" ON public.users;
DROP POLICY IF EXISTS "users_update_own" ON public.users;
DROP POLICY IF EXISTS "restaurants_public_read" ON public.restaurants;
DROP POLICY IF EXISTS "restaurants_owner_write" ON public.restaurants;
DROP POLICY IF EXISTS "orders_own_data" ON public.orders;
DROP POLICY IF EXISTS "order_items_own_data" ON public.order_items;

-- Eliminar cualquier política con nombres genéricos
DO $$
DECLARE
    pol record;
BEGIN
    FOR pol IN 
        SELECT schemaname, tablename, policyname 
        FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename IN ('users', 'restaurants', 'orders', 'order_items')
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', pol.policyname, pol.schemaname, pol.tablename);
    END LOOP;
END $$;

-- 3️⃣ CREAR POLÍTICAS ULTRA-SIMPLES (SIN RECURSIÓN)

-- USERS: Solo lectura/escritura de su propio registro
CREATE POLICY "users_select" ON public.users FOR SELECT TO authenticated
USING (id = auth.uid());

CREATE POLICY "users_update" ON public.users FOR UPDATE TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- RESTAURANTS: Lectura pública, escritura solo para dueño
CREATE POLICY "restaurants_select" ON public.restaurants FOR SELECT TO authenticated
USING (true);

CREATE POLICY "restaurants_insert" ON public.restaurants FOR INSERT TO authenticated
WITH CHECK (user_id::uuid = auth.uid());

CREATE POLICY "restaurants_update" ON public.restaurants FOR UPDATE TO authenticated
USING (user_id::uuid = auth.uid())
WITH CHECK (user_id::uuid = auth.uid());

-- ORDERS: Solo propias órdenes
CREATE POLICY "orders_select" ON public.orders FOR SELECT TO authenticated
USING (user_id::uuid = auth.uid());

CREATE POLICY "orders_insert" ON public.orders FOR INSERT TO authenticated
WITH CHECK (user_id::uuid = auth.uid());

CREATE POLICY "orders_update" ON public.orders FOR UPDATE TO authenticated
USING (user_id::uuid = auth.uid())
WITH CHECK (user_id::uuid = auth.uid());

-- ORDER_ITEMS: Solo items de órdenes propias (SIN JOINS)
CREATE POLICY "order_items_select" ON public.order_items FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.orders 
        WHERE orders.id = order_items.order_id 
        AND orders.user_id::uuid = auth.uid()
    )
);

CREATE POLICY "order_items_insert" ON public.order_items FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.orders 
        WHERE orders.id = order_items.order_id 
        AND orders.user_id::uuid = auth.uid()
    )
);

-- 4️⃣ HABILITAR RLS DE NUEVO
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

-- 5️⃣ VERIFICAR QUE NO HAY RECURSIÓN
SELECT 
    schemaname,
    tablename, 
    policyname,
    CASE 
        WHEN policyname LIKE '%recursive%' OR qual LIKE '%auth.uid%auth.uid%' 
        THEN '🚨 POSIBLE RECURSIÓN' 
        ELSE '✅ OK' 
    END as status
FROM pg_policies 
WHERE schemaname = 'public' 
AND tablename IN ('users', 'restaurants', 'orders', 'order_items')
ORDER BY tablename, policyname;