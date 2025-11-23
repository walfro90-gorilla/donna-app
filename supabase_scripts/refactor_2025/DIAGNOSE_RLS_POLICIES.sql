-- ============================================================================
-- DIAGNÓSTICO COMPLETO: RLS POLICIES Y PERMISOS
-- ============================================================================

\echo '🔍 ========== 1. POLÍTICAS RLS EN public.users =========='
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'users' 
  AND schemaname = 'public'
ORDER BY policyname;

\echo ''
\echo '🔍 ========== 2. ¿RLS HABILITADO EN public.users? =========='
SELECT 
    schemaname,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables 
WHERE tablename = 'users' 
  AND schemaname = 'public';

\echo ''
\echo '🔍 ========== 3. PERMISOS DE FUNCIÓN handle_user_signup() =========='
SELECT 
    p.proname as function_name,
    pg_get_function_identity_arguments(p.oid) as arguments,
    p.prosecdef as is_security_definer,
    r.rolname as owner,
    p.proconfig as configuration
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
LEFT JOIN pg_roles r ON p.proowner = r.oid
WHERE n.nspname = 'public'
  AND p.proname = 'handle_user_signup'
ORDER BY p.proname;

\echo ''
\echo '🔍 ========== 4. TRIGGERS EN auth.users =========='
SELECT 
    tgname as trigger_name,
    tgtype,
    tgenabled as enabled,
    pg_get_triggerdef(oid) as trigger_definition
FROM pg_trigger
WHERE tgrelid = 'auth.users'::regclass
  AND tgname LIKE '%signup%'
ORDER BY tgname;

\echo ''
\echo '🔍 ========== 5. ¿EXISTE TRIGGER PARA EMAIL CONFIRMATION? =========='
SELECT 
    tgname as trigger_name,
    tgtype,
    tgenabled as enabled,
    pg_get_triggerdef(oid) as trigger_definition
FROM pg_trigger
WHERE tgrelid = 'auth.users'::regclass
  AND (tgname LIKE '%email%' OR tgname LIKE '%confirm%')
ORDER BY tgname;

\echo ''
\echo '🔍 ========== 6. GRANTS EN public.users =========='
SELECT 
    grantee,
    privilege_type,
    is_grantable
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'users'
ORDER BY grantee, privilege_type;

\echo ''
\echo '✅ DIAGNÓSTICO COMPLETO - ENVÍA TODO EL OUTPUT'
