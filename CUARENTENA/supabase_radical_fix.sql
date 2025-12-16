-- ============================================
-- SOLUCIÓN RADICAL: ELIMINAR RECURSIÓN INFINITA
-- ============================================

-- 1. DESHABILITAR RLS EN TODAS LAS TABLAS
ALTER TABLE public.users DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.donations DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.recipients DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.distribution_events DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.reservations DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;

-- 2. ELIMINAR TODAS LAS POLÍTICAS EXISTENTES
DROP POLICY IF EXISTS users_policy ON public.users;
DROP POLICY IF EXISTS restaurants_policy ON public.restaurants;
DROP POLICY IF EXISTS donations_policy ON public.donations;
DROP POLICY IF EXISTS categories_policy ON public.categories;
DROP POLICY IF EXISTS recipients_policy ON public.recipients;
DROP POLICY IF EXISTS distribution_events_policy ON public.distribution_events;
DROP POLICY IF EXISTS reservations_policy ON public.reservations;
DROP POLICY IF EXISTS messages_policy ON public.messages;

-- 3. PERMITIR ACCESO COMPLETO A USUARIOS AUTENTICADOS
-- (Sin RLS por ahora para evitar recursión)

-- 4. OPCIONAL: Si quieres RLS simple más tarde, descomenta estas líneas:
/*
-- Habilitar RLS con políticas simples
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY users_simple_policy ON public.users 
    FOR ALL USING (auth.uid() = id);

ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurants_simple_policy ON public.restaurants 
    FOR ALL USING (true); -- Acceso público para restaurantes

ALTER TABLE public.donations ENABLE ROW LEVEL SECURITY;
CREATE POLICY donations_simple_policy ON public.donations 
    FOR ALL USING (true); -- Acceso público para donaciones
*/

-- ============================================
-- RESULTADO: Sin RLS = Sin recursión infinita
-- ============================================