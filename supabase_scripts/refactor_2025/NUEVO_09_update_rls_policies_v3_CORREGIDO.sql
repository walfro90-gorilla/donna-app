-- =====================================================================
-- 09_update_rls_policies_v3_CORREGIDO.sql
-- =====================================================================
-- Crea políticas RLS para las tablas correctas según DATABASE_SCHEMA.sql:
--   • public.users
--   • public.client_profiles
--   • public.restaurants
--   • public.delivery_agent_profiles
--   • public.user_preferences
--   • public.accounts
--
-- EJECUTAR DESPUÉS DE: 09_cleanup_all_policies.sql
-- =====================================================================

-- ====================================
-- HABILITAR RLS EN TODAS LAS TABLAS
-- ====================================
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_agent_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

-- ====================================
-- POLÍTICAS PARA: public.users
-- ====================================

-- SELECT: Los usuarios pueden ver su propio registro
DROP POLICY IF EXISTS users_select_own ON public.users;
CREATE POLICY users_select_own ON public.users
  FOR SELECT
  TO authenticated
  USING (id = auth.uid());

-- INSERT: Los usuarios pueden crear su propio registro
DROP POLICY IF EXISTS users_insert_self ON public.users;
CREATE POLICY users_insert_self ON public.users
  FOR INSERT
  TO authenticated
  WITH CHECK (id = auth.uid());

-- UPDATE: Los usuarios pueden actualizar su propio registro
DROP POLICY IF EXISTS users_update_own ON public.users;
CREATE POLICY users_update_own ON public.users
  FOR UPDATE
  TO authenticated
  USING (id = auth.uid());

-- SELECT: Los admins pueden ver todos los usuarios
DROP POLICY IF EXISTS users_select_admin ON public.users;
CREATE POLICY users_select_admin ON public.users
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users u 
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- ====================================
-- POLÍTICAS PARA: client_profiles
-- ====================================

-- SELECT: Los clientes pueden ver su propio perfil
DROP POLICY IF EXISTS client_profiles_select_own ON public.client_profiles;
CREATE POLICY client_profiles_select_own ON public.client_profiles
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- INSERT: Los clientes pueden crear su propio perfil
DROP POLICY IF EXISTS client_profiles_insert_self ON public.client_profiles;
CREATE POLICY client_profiles_insert_self ON public.client_profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- UPDATE: Los clientes pueden actualizar su propio perfil
DROP POLICY IF EXISTS client_profiles_update_own ON public.client_profiles;
CREATE POLICY client_profiles_update_own ON public.client_profiles
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid());

-- SELECT: Los admins pueden ver todos los perfiles de clientes
DROP POLICY IF EXISTS client_profiles_select_admin ON public.client_profiles;
CREATE POLICY client_profiles_select_admin ON public.client_profiles
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users u 
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- ====================================
-- POLÍTICAS PARA: restaurants
-- ====================================

-- SELECT: Todos pueden ver restaurantes aprobados
DROP POLICY IF EXISTS restaurants_select_public ON public.restaurants;
CREATE POLICY restaurants_select_public ON public.restaurants
  FOR SELECT
  TO authenticated, anon
  USING (status = 'approved');

-- SELECT: Los restaurantes pueden ver su propio perfil (cualquier status)
DROP POLICY IF EXISTS restaurants_select_own ON public.restaurants;
CREATE POLICY restaurants_select_own ON public.restaurants
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- INSERT: Los restaurantes pueden crear su propio perfil
DROP POLICY IF EXISTS restaurants_insert_self ON public.restaurants;
CREATE POLICY restaurants_insert_self ON public.restaurants
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- UPDATE: Los restaurantes pueden actualizar su propio perfil
DROP POLICY IF EXISTS restaurants_update_own ON public.restaurants;
CREATE POLICY restaurants_update_own ON public.restaurants
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid());

-- SELECT: Los admins pueden ver todos los restaurantes
DROP POLICY IF EXISTS restaurants_select_admin ON public.restaurants;
CREATE POLICY restaurants_select_admin ON public.restaurants
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users u 
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- UPDATE: Los admins pueden actualizar cualquier restaurante
DROP POLICY IF EXISTS restaurants_update_admin ON public.restaurants;
CREATE POLICY restaurants_update_admin ON public.restaurants
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users u 
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- ====================================
-- POLÍTICAS PARA: delivery_agent_profiles
-- ====================================

-- SELECT: Los repartidores pueden ver su propio perfil
DROP POLICY IF EXISTS delivery_agent_profiles_select_own ON public.delivery_agent_profiles;
CREATE POLICY delivery_agent_profiles_select_own ON public.delivery_agent_profiles
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- INSERT: Los repartidores pueden crear su propio perfil
DROP POLICY IF EXISTS delivery_agent_profiles_insert_self ON public.delivery_agent_profiles;
CREATE POLICY delivery_agent_profiles_insert_self ON public.delivery_agent_profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- UPDATE: Los repartidores pueden actualizar su propio perfil
DROP POLICY IF EXISTS delivery_agent_profiles_update_own ON public.delivery_agent_profiles;
CREATE POLICY delivery_agent_profiles_update_own ON public.delivery_agent_profiles
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid());

-- SELECT: Los admins pueden ver todos los perfiles de repartidores
DROP POLICY IF EXISTS delivery_agent_profiles_select_admin ON public.delivery_agent_profiles;
CREATE POLICY delivery_agent_profiles_select_admin ON public.delivery_agent_profiles
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users u 
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- UPDATE: Los admins pueden actualizar cualquier perfil de repartidor
DROP POLICY IF EXISTS delivery_agent_profiles_update_admin ON public.delivery_agent_profiles;
CREATE POLICY delivery_agent_profiles_update_admin ON public.delivery_agent_profiles
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users u 
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- ====================================
-- POLÍTICAS PARA: user_preferences
-- ====================================

-- SELECT: Los usuarios pueden ver sus propias preferencias
DROP POLICY IF EXISTS user_preferences_select_own ON public.user_preferences;
CREATE POLICY user_preferences_select_own ON public.user_preferences
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- INSERT: Los usuarios pueden crear sus propias preferencias
DROP POLICY IF EXISTS user_preferences_insert_self ON public.user_preferences;
CREATE POLICY user_preferences_insert_self ON public.user_preferences
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- UPDATE: Los usuarios pueden actualizar sus propias preferencias
DROP POLICY IF EXISTS user_preferences_update_own ON public.user_preferences;
CREATE POLICY user_preferences_update_own ON public.user_preferences
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid());

-- ====================================
-- POLÍTICAS PARA: accounts
-- ====================================

-- SELECT: Los usuarios pueden ver sus propias cuentas
DROP POLICY IF EXISTS accounts_select_own ON public.accounts;
CREATE POLICY accounts_select_own ON public.accounts
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- INSERT: Los usuarios pueden crear sus propias cuentas
DROP POLICY IF EXISTS accounts_insert_self ON public.accounts;
CREATE POLICY accounts_insert_self ON public.accounts
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- UPDATE: Los usuarios pueden actualizar sus propias cuentas
DROP POLICY IF EXISTS accounts_update_own ON public.accounts;
CREATE POLICY accounts_update_own ON public.accounts
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid());

-- SELECT: Los admins pueden ver todas las cuentas
DROP POLICY IF EXISTS accounts_select_admin ON public.accounts;
CREATE POLICY accounts_select_admin ON public.accounts
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users u 
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- UPDATE: Los admins pueden actualizar cualquier cuenta
DROP POLICY IF EXISTS accounts_update_admin ON public.accounts;
CREATE POLICY accounts_update_admin ON public.accounts
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users u 
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- ====================================
-- VERIFICACIÓN FINAL
-- ====================================
SELECT 
  '✅ POLÍTICAS RLS CREADAS EXITOSAMENTE' as status,
  COUNT(*) as total_policies
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('users', 'client_profiles', 'restaurants', 'delivery_agent_profiles', 'user_preferences', 'accounts');

-- Ver todas las políticas creadas
SELECT 
  tablename,
  policyname,
  cmd as command,
  CASE 
    WHEN roles = '{authenticated}' THEN 'authenticated'
    WHEN roles = '{anon}' THEN 'anon'
    WHEN roles = '{authenticated,anon}' THEN 'authenticated, anon'
    ELSE roles::text
  END as roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('users', 'client_profiles', 'restaurants', 'delivery_agent_profiles', 'user_preferences', 'accounts')
ORDER BY tablename, policyname;
