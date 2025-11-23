-- ============================================================
-- DIAGNÓSTICO: Relación entre auth.users y public.users
-- ============================================================
-- Ejecuta este script en SQL Editor de Supabase
-- Copia TODOS los resultados y envíalos
-- ============================================================

-- 1. Ver estructura de public.users
SELECT 
    '1_PUBLIC_USERS_COLUMNS' AS step,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'users'
ORDER BY ordinal_position;

-- 2. Ver constraints en public.users
SELECT
    '2_PUBLIC_USERS_CONSTRAINTS' AS step,
    conname AS constraint_name,
    contype AS constraint_type,
    pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.users'::regclass
ORDER BY conname;

-- 3. Ver si hay FK desde auth.users hacia public.users (poco común pero posible)
SELECT
    '3_FK_FROM_AUTH_TO_PUBLIC' AS step,
    tc.constraint_name,
    tc.table_schema,
    tc.table_name,
    kcu.column_name,
    ccu.table_schema AS foreign_table_schema,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'auth'
  AND tc.table_name = 'users';

-- 4. Ver triggers en public.users
SELECT 
    '4_PUBLIC_USERS_TRIGGERS' AS step,
    trigger_name,
    event_manipulation,
    action_statement,
    action_timing
FROM information_schema.triggers
WHERE event_object_schema = 'public' 
  AND event_object_table = 'users'
ORDER BY trigger_name;

-- 5. Ver políticas RLS en public.users
SELECT 
    '5_PUBLIC_USERS_RLS' AS step,
    policyname,
    permissive,
    roles::text AS roles,
    cmd,
    qual::text AS using_expression,
    with_check::text AS with_check_expression
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'users'
ORDER BY policyname;

-- 6. Intentar simular el INSERT que hace Supabase Auth (como service_role)
SELECT 
    '6_TEST_CAN_INSERT_AUTH_USER' AS step,
    'Checking if service_role can INSERT into auth.users...' AS message;

-- Ver permisos del rol service_role en auth.users
SELECT
    '7_SERVICE_ROLE_GRANTS' AS step,
    grantee,
    privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'auth'
  AND table_name = 'users'
  AND grantee IN ('service_role', 'authenticator', 'supabase_auth_admin')
ORDER BY grantee, privilege_type;
