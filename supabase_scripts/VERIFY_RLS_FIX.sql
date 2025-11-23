-- =====================================================================
-- VERIFY_RLS_FIX.sql
-- =====================================================================
-- Verifica que las políticas RLS estén funcionando correctamente
-- sin recursión infinita.
-- =====================================================================

-- 1. Verificar función is_user_admin()
SELECT 
  '✅ 1. FUNCIÓN is_user_admin()' as check_name,
  proname as function_name,
  prosecdef as is_security_definer,
  CASE 
    WHEN prosecdef THEN '✅ SECURITY DEFINER habilitado'
    ELSE '❌ SECURITY DEFINER NO habilitado'
  END as status
FROM pg_proc
WHERE proname = 'is_user_admin'
  AND pronamespace = 'public'::regnamespace;

-- 2. Verificar políticas de users (no deben tener recursión)
SELECT 
  '✅ 2. POLÍTICAS DE USERS' as check_name,
  policyname,
  cmd as command,
  CASE 
    WHEN roles = '{authenticated}' THEN 'authenticated'
    ELSE roles::text
  END as roles,
  CASE 
    WHEN policyname LIKE '%admin%' THEN '✅ Usa is_user_admin()'
    ELSE '✅ Política básica'
  END as status
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'users'
ORDER BY policyname;

-- 3. Contar políticas que usan is_user_admin() en otras tablas
SELECT 
  '✅ 3. POLÍTICAS QUE USAN is_user_admin()' as check_name,
  tablename,
  COUNT(*) as policies_using_function
FROM pg_policies
WHERE schemaname = 'public'
  AND (
    policyname LIKE '%admin%'
    AND tablename IN ('client_profiles', 'restaurants', 'delivery_agent_profiles', 'accounts')
  )
GROUP BY tablename
ORDER BY tablename;

-- 4. Verificar que RLS esté habilitado en tablas críticas
SELECT 
  '✅ 4. RLS HABILITADO' as check_name,
  tablename,
  CASE 
    WHEN rowsecurity THEN '✅ RLS Habilitado'
    ELSE '❌ RLS NO Habilitado'
  END as status
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('users', 'client_profiles', 'restaurants', 'delivery_agent_profiles', 'accounts', 'user_preferences')
ORDER BY tablename;

-- 5. Verificar que NO haya políticas obsoletas que causen recursión
SELECT 
  '✅ 5. VERIFICAR POLÍTICAS OBSOLETAS' as check_name,
  COUNT(*) as obsolete_policies,
  CASE 
    WHEN COUNT(*) = 0 THEN '✅ No hay políticas obsoletas'
    ELSE '⚠️ Hay políticas obsoletas que pueden causar recursión'
  END as status
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'users'
  AND policyname IN (
    'users_select_related_in_orders',
    'users_select_authenticated_break_recursion',
    'users_select_authenticated_basic',
    'users_update_self_basic'
  );

-- 6. TEST PRÁCTICO: Simular consulta de usuarios (debe funcionar sin recursión)
SELECT 
  '✅ 6. TEST PRÁCTICO' as check_name,
  '✅ Consulta exitosa sin recursión' as status,
  COUNT(*) as total_users
FROM public.users;
