-- ELIMINAMOS TODAS LAS POLÍTICAS EXISTENTES Y RECREAMOS CON TIPOS CORRECTOS
-- Deshabilitar RLS temporalmente
ALTER TABLE public.users DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items DISABLE ROW LEVEL SECURITY;

-- Eliminar todas las políticas existentes
DROP POLICY IF EXISTS "users_select_own" ON public.users;
DROP POLICY IF EXISTS "users_update_own" ON public.users;
DROP POLICY IF EXISTS "restaurants_select_all" ON public.restaurants;
DROP POLICY IF EXISTS "restaurants_update_owner" ON public.restaurants;
DROP POLICY IF EXISTS "orders_select_own" ON public.orders;
DROP POLICY IF EXISTS "orders_insert_own" ON public.orders;
DROP POLICY IF EXISTS "orders_update_own" ON public.orders;
DROP POLICY IF EXISTS "order_items_select_own" ON public.order_items;
DROP POLICY IF EXISTS "order_items_insert_own" ON public.order_items;

-- POLÍTICAS PARA USERS (solo pueden ver/editar su propio perfil)
CREATE POLICY "users_select_own" ON public.users
    FOR SELECT USING (auth.uid() = id::uuid);

CREATE POLICY "users_update_own" ON public.users
    FOR UPDATE USING (auth.uid() = id::uuid);

-- POLÍTICAS PARA RESTAURANTS (todos pueden ver, solo dueños pueden editar)
CREATE POLICY "restaurants_select_all" ON public.restaurants
    FOR SELECT USING (true);

CREATE POLICY "restaurants_update_owner" ON public.restaurants
    FOR UPDATE USING (auth.uid() = user_id::uuid);

-- POLÍTICAS PARA ORDERS (usuarios solo ven sus propias órdenes)
CREATE POLICY "orders_select_own" ON public.orders
    FOR SELECT USING (auth.uid() = user_id::uuid);

CREATE POLICY "orders_insert_own" ON public.orders
    FOR INSERT WITH CHECK (auth.uid() = user_id::uuid);

CREATE POLICY "orders_update_own" ON public.orders
    FOR UPDATE USING (auth.uid() = user_id::uuid);

-- POLÍTICAS PARA ORDER_ITEMS (solo ven items de sus órdenes)
CREATE POLICY "order_items_select_own" ON public.order_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.orders 
            WHERE orders.id = order_items.order_id 
            AND orders.user_id::uuid = auth.uid()
        )
    );

CREATE POLICY "order_items_insert_own" ON public.order_items
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.orders 
            WHERE orders.id = order_items.order_id 
            AND orders.user_id::uuid = auth.uid()
        )
    );

-- Habilitar RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;