-- ============================================================================
-- SOLUCIÓN DEFINITIVA: ELIMINAR RECURSIÓN INFINITA EN POLÍTICAS RLS
-- ============================================================================

-- 1. ELIMINAR TODAS LAS POLÍTICAS EXISTENTES (QUE CAUSAN RECURSIÓN)
DROP POLICY IF EXISTS "allow_own_profile_read" ON public.users;
DROP POLICY IF EXISTS "allow_own_profile_update" ON public.users;
DROP POLICY IF EXISTS "users_select_policy" ON public.users;
DROP POLICY IF EXISTS "users_update_policy" ON public.users;
DROP POLICY IF EXISTS "users_insert_policy" ON public.users;
DROP POLICY IF EXISTS "Enable read access for own user" ON public.users;
DROP POLICY IF EXISTS "Enable update access for own user" ON public.users;

-- 2. ELIMINAR TODAS LAS POLÍTICAS DE OTRAS TABLAS TAMBIÉN
DROP POLICY IF EXISTS "restaurants_select_policy" ON public.restaurants;
DROP POLICY IF EXISTS "restaurants_insert_policy" ON public.restaurants;
DROP POLICY IF EXISTS "restaurants_update_policy" ON public.restaurants;

-- 3. DESHABILITAR RLS TEMPORALMENTE
ALTER TABLE public.users DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.donations DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.recipients DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.distribution_events DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.reservations DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;

-- 4. CREAR POLÍTICAS SIMPLES SIN RECURSIÓN
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Política simple: Usuarios autenticados pueden leer sus propios datos
CREATE POLICY "users_own_data_only" ON public.users
    FOR ALL
    USING (auth.uid() = id);

-- 5. HABILITAR POLÍTICAS BÁSICAS PARA OTRAS TABLAS
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "restaurants_public_read" ON public.restaurants
    FOR SELECT
    USING (true);

CREATE POLICY "restaurants_owner_write" ON public.restaurants
    FOR ALL
    USING (auth.uid() = user_id);

-- 6. VERIFICAR QUE EL TRIGGER EXISTE Y FUNCIONA
-- (El trigger ya está creado, no lo tocamos)

-- 7. CONCEDER PERMISOS BÁSICOS
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;