-- POLÍTICAS RLS PARA APP DE REPARTO - BASADO EN SCHEMA REAL
-- Basándome en el screenshot de tu schema, estas son las tablas que veo

-- 1. DESACTIVAR RLS EN TODAS LAS TABLAS PRIMERO
ALTER TABLE IF EXISTS public.users DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.restaurants DISABLE ROW LEVEL SECURITY;  
ALTER TABLE IF EXISTS public.orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.order_items DISABLE ROW LEVEL SECURITY;

-- 2. ELIMINAR TODAS LAS POLÍTICAS EXISTENTES
DROP POLICY IF EXISTS "users_select_own" ON public.users;
DROP POLICY IF EXISTS "users_update_own" ON public.users;
DROP POLICY IF EXISTS "restaurants_select_all" ON public.restaurants;
DROP POLICY IF EXISTS "restaurants_update_own" ON public.restaurants;
DROP POLICY IF EXISTS "orders_select_related" ON public.orders;
DROP POLICY IF EXISTS "orders_insert_own" ON public.orders;
DROP POLICY IF EXISTS "orders_update_related" ON public.orders;
DROP POLICY IF EXISTS "order_items_select_related" ON public.order_items;
DROP POLICY IF EXISTS "order_items_insert_own" ON public.order_items;
DROP POLICY IF EXISTS "order_items_update_related" ON public.order_items;

-- 3. CREAR POLÍTICAS SIMPLES SIN RECURSIÓN

-- USERS TABLE - Solo pueden ver su propio perfil
CREATE POLICY "users_select_own" ON public.users
    FOR SELECT 
    USING (auth.uid() = id);

CREATE POLICY "users_update_own" ON public.users  
    FOR UPDATE
    USING (auth.uid() = id);

-- RESTAURANTS TABLE - Todos pueden ver, solo dueños pueden editar
CREATE POLICY "restaurants_select_all" ON public.restaurants
    FOR SELECT 
    USING (true);

CREATE POLICY "restaurants_update_own" ON public.restaurants
    FOR UPDATE
    USING (auth.uid() = user_id);

-- ORDERS TABLE - Usuarios ven sus órdenes, restaurantes ven órdenes asignadas, repartidores ven órdenes asignadas
CREATE POLICY "orders_select_related" ON public.orders
    FOR SELECT
    USING (
        auth.uid() = user_id OR
        auth.uid() = delivery_user_id OR
        auth.uid() IN (SELECT user_id FROM public.restaurants WHERE id = restaurant_id)
    );

CREATE POLICY "orders_insert_own" ON public.orders
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "orders_update_related" ON public.orders
    FOR UPDATE
    USING (
        auth.uid() = user_id OR
        auth.uid() = delivery_user_id OR  
        auth.uid() IN (SELECT user_id FROM public.restaurants WHERE id = restaurant_id)
    );

-- ORDER_ITEMS TABLE - Acceso basado en la orden relacionada
CREATE POLICY "order_items_select_related" ON public.order_items
    FOR SELECT
    USING (
        order_id IN (
            SELECT id FROM public.orders 
            WHERE auth.uid() = user_id OR
                  auth.uid() = delivery_user_id OR
                  auth.uid() IN (SELECT user_id FROM public.restaurants WHERE id = restaurant_id)
        )
    );

CREATE POLICY "order_items_insert_own" ON public.order_items
    FOR INSERT
    WITH CHECK (
        order_id IN (
            SELECT id FROM public.orders 
            WHERE auth.uid() = user_id
        )
    );

-- 4. REACTIVAR RLS EN TODAS LAS TABLAS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;  
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

-- 5. VERIFICAR QUE TODO ESTÉ CONFIGURADO
SELECT schemaname, tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('users', 'restaurants', 'orders', 'order_items');