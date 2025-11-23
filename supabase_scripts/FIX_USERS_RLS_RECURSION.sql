-- =====================================================================
-- FIX_USERS_RLS_RECURSION.sql
-- =====================================================================
-- SOLUCIÓN DEFINITIVA para la recursión infinita en políticas RLS de users
--
-- PROBLEMA:
-- La política users_select_admin hacía recursión infinita:
--   SELECT * FROM users WHERE (EXISTS (SELECT 1 FROM users ...))
--                                              ^^^^^^ ¡Recursión!
--
-- SOLUCIÓN:
-- Crear función SECURITY DEFINER que bypasea RLS para verificar rol.
-- =====================================================================

-- ====================================
-- 1. FUNCIÓN SEGURA PARA VERIFICAR ROL
-- ====================================

-- Eliminar función anterior si existe
DROP FUNCTION IF EXISTS public.is_user_admin(uuid);

-- Función SECURITY DEFINER que bypasea RLS
CREATE OR REPLACE FUNCTION public.is_user_admin(user_uuid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER -- ✅ Ejecuta con permisos del OWNER (bypasea RLS)
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.users 
    WHERE id = user_uuid 
      AND role = 'admin'
  );
$$;

-- Grant EXECUTE a authenticated
GRANT EXECUTE ON FUNCTION public.is_user_admin(uuid) TO authenticated;

-- ====================================
-- 2. RECREAR POLÍTICAS SIN RECURSIÓN
-- ====================================

-- ELIMINAR TODAS LAS POLÍTICAS DE USERS
DROP POLICY IF EXISTS users_select_own ON public.users;
DROP POLICY IF EXISTS users_insert_self ON public.users;
DROP POLICY IF EXISTS users_update_own ON public.users;
DROP POLICY IF EXISTS users_select_admin ON public.users;
DROP POLICY IF EXISTS users_update_admin ON public.users;
DROP POLICY IF EXISTS users_select_related_in_orders ON public.users;
DROP POLICY IF EXISTS users_select_authenticated_break_recursion ON public.users;
DROP POLICY IF EXISTS users_select_authenticated_basic ON public.users;
DROP POLICY IF EXISTS users_update_self_basic ON public.users;

-- SELECT: Los usuarios pueden ver su propio registro
CREATE POLICY users_select_own ON public.users
  FOR SELECT
  TO authenticated
  USING (id = auth.uid());

-- INSERT: Los usuarios pueden crear su propio registro
CREATE POLICY users_insert_self ON public.users
  FOR INSERT
  TO authenticated
  WITH CHECK (id = auth.uid());

-- UPDATE: Los usuarios pueden actualizar su propio registro
CREATE POLICY users_update_own ON public.users
  FOR UPDATE
  TO authenticated
  USING (id = auth.uid());

-- SELECT: Los admins pueden ver todos los usuarios ✅ SIN RECURSIÓN
CREATE POLICY users_select_admin ON public.users
  FOR SELECT
  TO authenticated
  USING (public.is_user_admin()); -- ✅ Usa función SECURITY DEFINER

-- UPDATE: Los admins pueden actualizar cualquier usuario ✅ SIN RECURSIÓN
CREATE POLICY users_update_admin ON public.users
  FOR UPDATE
  TO authenticated
  USING (public.is_user_admin()); -- ✅ Usa función SECURITY DEFINER

-- ====================================
-- 3. ACTUALIZAR POLÍTICAS DE OTRAS TABLAS
-- ====================================

-- client_profiles: admin puede ver todos
DROP POLICY IF EXISTS client_profiles_select_admin ON public.client_profiles;
CREATE POLICY client_profiles_select_admin ON public.client_profiles
  FOR SELECT
  TO authenticated
  USING (public.is_user_admin()); -- ✅ SIN RECURSIÓN

-- restaurants: admin puede ver todos
DROP POLICY IF EXISTS restaurants_select_admin ON public.restaurants;
CREATE POLICY restaurants_select_admin ON public.restaurants
  FOR SELECT
  TO authenticated
  USING (public.is_user_admin()); -- ✅ SIN RECURSIÓN

DROP POLICY IF EXISTS restaurants_update_admin ON public.restaurants;
CREATE POLICY restaurants_update_admin ON public.restaurants
  FOR UPDATE
  TO authenticated
  USING (public.is_user_admin()); -- ✅ SIN RECURSIÓN

-- delivery_agent_profiles: admin puede ver todos
DROP POLICY IF EXISTS delivery_agent_profiles_select_admin ON public.delivery_agent_profiles;
CREATE POLICY delivery_agent_profiles_select_admin ON public.delivery_agent_profiles
  FOR SELECT
  TO authenticated
  USING (public.is_user_admin()); -- ✅ SIN RECURSIÓN

DROP POLICY IF EXISTS delivery_agent_profiles_update_admin ON public.delivery_agent_profiles;
CREATE POLICY delivery_agent_profiles_update_admin ON public.delivery_agent_profiles
  FOR UPDATE
  TO authenticated
  USING (public.is_user_admin()); -- ✅ SIN RECURSIÓN

-- accounts: admin puede ver todas
DROP POLICY IF EXISTS accounts_select_admin ON public.accounts;
CREATE POLICY accounts_select_admin ON public.accounts
  FOR SELECT
  TO authenticated
  USING (public.is_user_admin()); -- ✅ SIN RECURSIÓN

DROP POLICY IF EXISTS accounts_update_admin ON public.accounts;
CREATE POLICY accounts_update_admin ON public.accounts
  FOR UPDATE
  TO authenticated
  USING (public.is_user_admin()); -- ✅ SIN RECURSIÓN

-- ====================================
-- 4. VERIFICACIÓN FINAL
-- ====================================

-- Verificar función creada
SELECT 
  '✅ Función is_user_admin() creada' as status,
  proname as function_name,
  prosecdef as is_security_definer
FROM pg_proc
WHERE proname = 'is_user_admin';

-- Verificar políticas
SELECT 
  '✅ POLÍTICAS RLS RECREADAS SIN RECURSIÓN' as status,
  COUNT(*) as total_policies
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'users';

-- Ver políticas de users
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
  AND tablename = 'users'
ORDER BY policyname;
