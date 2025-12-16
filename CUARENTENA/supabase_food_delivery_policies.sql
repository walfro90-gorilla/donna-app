-- ========================================
-- POLÍTICAS RLS PARA APP DE REPARTO DE COMIDAS
-- ========================================
-- Basado en el schema real de la base de datos

-- Limpiar políticas existentes
DROP POLICY IF EXISTS "users_select_own" ON public.users;
DROP POLICY IF EXISTS "users_update_own" ON public.users;
DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_insert_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;
DROP POLICY IF EXISTS "restaurants_select_policy" ON public.restaurants;
DROP POLICY IF EXISTS "restaurants_update_policy" ON public.restaurants;
DROP POLICY IF EXISTS "menu_items_select_policy" ON public.menu_items;
DROP POLICY IF EXISTS "menu_items_insert_policy" ON public.menu_items;
DROP POLICY IF EXISTS "menu_items_update_policy" ON public.menu_items;
DROP POLICY IF EXISTS "order_items_select_policy" ON public.order_items;
DROP POLICY IF EXISTS "order_items_insert_policy" ON public.order_items;

-- Habilitar RLS en todas las tablas
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

-- ========================================
-- POLÍTICAS PARA TABLA USERS
-- ========================================

-- Los usuarios pueden ver y actualizar solo su propio perfil
CREATE POLICY "users_select_own" ON public.users
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "users_update_own" ON public.users
    FOR UPDATE USING (auth.uid() = id);

-- ========================================
-- POLÍTICAS PARA TABLA RESTAURANTS
-- ========================================

-- Todos pueden ver los restaurantes (para el catálogo)
CREATE POLICY "restaurants_select_all" ON public.restaurants
    FOR SELECT USING (true);

-- Solo el dueño del restaurante puede actualizar su información
CREATE POLICY "restaurants_update_own" ON public.restaurants
    FOR UPDATE USING (owner_id = auth.uid());

-- ========================================
-- POLÍTICAS PARA TABLA MENU_ITEMS
-- ========================================

-- Todos pueden ver los items del menú
CREATE POLICY "menu_items_select_all" ON public.menu_items
    FOR SELECT USING (true);

-- Solo el dueño del restaurante puede crear/actualizar items del menú
CREATE POLICY "menu_items_insert_restaurant_owner" ON public.menu_items
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.restaurants r 
            WHERE r.id = restaurant_id AND r.owner_id = auth.uid()
        )
    );

CREATE POLICY "menu_items_update_restaurant_owner" ON public.menu_items
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM public.restaurants r 
            WHERE r.id = restaurant_id AND r.owner_id = auth.uid()
        )
    );

-- ========================================
-- POLÍTICAS PARA TABLA ORDERS
-- ========================================

-- Los usuarios pueden ver sus propias órdenes
CREATE POLICY "orders_select_customer" ON public.orders
    FOR SELECT USING (customer_id = auth.uid());

-- Los restaurantes pueden ver órdenes de sus restaurantes
CREATE POLICY "orders_select_restaurant" ON public.orders
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.restaurants r 
            WHERE r.id = restaurant_id AND r.owner_id = auth.uid()
        )
    );

-- Los repartidores pueden ver órdenes asignadas a ellos
CREATE POLICY "orders_select_delivery" ON public.orders
    FOR SELECT USING (delivery_person_id = auth.uid());

-- Los clientes pueden crear órdenes
CREATE POLICY "orders_insert_customer" ON public.orders
    FOR INSERT WITH CHECK (customer_id = auth.uid());

-- Los restaurantes pueden actualizar el estado de sus órdenes
CREATE POLICY "orders_update_restaurant" ON public.orders
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM public.restaurants r 
            WHERE r.id = restaurant_id AND r.owner_id = auth.uid()
        )
    );

-- Los repartidores pueden actualizar órdenes asignadas a ellos
CREATE POLICY "orders_update_delivery" ON public.orders
    FOR UPDATE USING (delivery_person_id = auth.uid());

-- ========================================
-- POLÍTICAS PARA TABLA ORDER_ITEMS
-- ========================================

-- Los usuarios pueden ver items de sus propias órdenes
CREATE POLICY "order_items_select_customer" ON public.order_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.orders o 
            WHERE o.id = order_id AND o.customer_id = auth.uid()
        )
    );

-- Los restaurantes pueden ver items de órdenes de sus restaurantes
CREATE POLICY "order_items_select_restaurant" ON public.order_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.orders o 
            JOIN public.restaurants r ON r.id = o.restaurant_id
            WHERE o.id = order_id AND r.owner_id = auth.uid()
        )
    );

-- Los clientes pueden insertar items en sus órdenes
CREATE POLICY "order_items_insert_customer" ON public.order_items
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.orders o 
            WHERE o.id = order_id AND o.customer_id = auth.uid()
        )
    );

-- ========================================
-- VERIFICAR CONFIGURACIÓN
-- ========================================

-- Mostrar todas las políticas creadas
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies 
WHERE schemaname = 'public' 
ORDER BY tablename, policyname;

-- Verificar que RLS está habilitado
SELECT schemaname, tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('users', 'restaurants', 'menu_items', 'orders', 'order_items');