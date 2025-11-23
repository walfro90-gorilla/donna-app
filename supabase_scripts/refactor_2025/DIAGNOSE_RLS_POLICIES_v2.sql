-- ============================================================================
-- DIAGNÓSTICO COMPLETO: RLS POLICIES Y PERMISOS
-- ============================================================================

-- ========== 1. POLÍTICAS RLS EN public.users ==========
SELECT 
    '🔍 1. POLÍTICAS RLS' as section,
    policyname,
    permissive,
    roles::text,
    cmd,
    qual::text,
    with_check::text
FROM pg_policies 
WHERE tablename = 'users' 
  AND schemaname = 'public'
ORDER BY policyname;

-- ========== 2. ¿RLS HABILITADO EN public.users? ==========
SELECT 
    '🔍 2. RLS ENABLED' as section,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables 
WHERE tablename = 'users' 
  AND schemaname = 'public';

-- ========== 3. PERMISOS DE FUNCIÓN handle_user_signup() ==========
SELECT 
    '🔍 3. FUNCTION PERMS' as section,
    p.proname as function_name,
    pg_get_function_identity_arguments(p.oid) as arguments,
    p.prosecdef as is_security_definer,
    r.rolname as owner,
    p.proconfig::text as configuration
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
LEFT JOIN pg_roles r ON p.proowner = r.oid
WHERE n.nspname = 'public'
  AND p.proname = 'handle_user_signup'
ORDER BY p.proname;

-- ========== 4. TRIGGERS EN auth.users RELACIONADOS A SIGNUP ==========
SELECT 
    '🔍 4. SIGNUP TRIGGERS' as section,
    tgname as trigger_name,
    tgenabled as enabled,
    pg_get_triggerdef(oid) as trigger_definition
FROM pg_trigger
WHERE tgrelid = 'auth.users'::regclass
  AND tgname LIKE '%signup%'
ORDER BY tgname;

-- ========== 5. TRIGGERS PARA EMAIL CONFIRMATION ==========
SELECT 
    '🔍 5. EMAIL CONFIRM TRIGGERS' as section,
    tgname as trigger_name,
    tgenabled as enabled,
    pg_get_triggerdef(oid) as trigger_definition
FROM pg_trigger
WHERE tgrelid = 'auth.users'::regclass
  AND (tgname LIKE '%email%' OR tgname LIKE '%confirm%')
ORDER BY tgname;

-- ========== 6. TODOS LOS TRIGGERS EN auth.users ==========
SELECT 
    '🔍 6. ALL AUTH TRIGGERS' as section,
    tgname as trigger_name,
    tgenabled as enabled,
    CASE 
        WHEN tgtype & 2 = 2 THEN 'BEFORE'
        WHEN tgtype & 64 = 64 THEN 'INSTEAD OF'
        ELSE 'AFTER'
    END as timing,
    CASE 
        WHEN tgtype & 4 = 4 THEN 'INSERT'
        WHEN tgtype & 8 = 8 THEN 'DELETE'
        WHEN tgtype & 16 = 16 THEN 'UPDATE'
        ELSE 'OTHER'
    END as event
FROM pg_trigger
WHERE tgrelid = 'auth.users'::regclass
  AND NOT tgisinternal
ORDER BY tgname;

-- ========== 7. GRANTS EN public.users ==========
SELECT 
    '🔍 7. TABLE GRANTS' as section,
    grantee,
    privilege_type,
    is_grantable
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'users'
ORDER BY grantee, privilege_type;

-- ========== 8. VERIFICAR SI EXISTE OTRO TRIGGER DE EMAIL ==========
SELECT 
    '🔍 8. CHECK HANDLE_EMAIL_CONFIRM' as section,
    p.proname as function_name,
    pg_get_function_identity_arguments(p.oid) as arguments,
    p.prosecdef as is_security_definer
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND (p.proname LIKE '%email%' OR p.proname LIKE '%confirm%')
ORDER BY p.proname;

-- ✅ DIAGNÓSTICO COMPLETO
SELECT '✅ DIAGNÓSTICO COMPLETO - ENVÍA TODO EL OUTPUT' as resultado;
