-- ============================================================
-- DIAGNÓSTICO: Políticas RLS en auth.users
-- ============================================================
-- Ejecuta este script en SQL Editor de Supabase
-- Copia TODOS los resultados y envíalos
-- ============================================================

-- 1. Ver políticas RLS en auth.users
SELECT 
    '1_RLS_POLICIES' AS step,
    schemaname,
    tablename,
    policyname,
    permissive,
    roles::text AS roles,
    cmd,
    qual::text AS using_expression,
    with_check::text AS with_check_expression
FROM pg_policies
WHERE schemaname = 'auth' AND tablename = 'users'
ORDER BY policyname;

-- 2. Ver si RLS está habilitado en auth.users
SELECT 
    '2_RLS_STATUS' AS step,
    schemaname,
    tablename,
    rowsecurity AS rls_enabled
FROM pg_tables
WHERE schemaname = 'auth' AND tablename = 'users';

-- 3. Ver triggers en auth.users que podrían estar fallando
SELECT 
    '3_TRIGGERS' AS step,
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement,
    action_timing,
    action_orientation
FROM information_schema.triggers
WHERE event_object_schema = 'auth' 
  AND event_object_table = 'users'
ORDER BY trigger_name;

-- 4. Ver constraints que podrían estar siendo violados
SELECT
    '4_CONSTRAINTS' AS step,
    conname AS constraint_name,
    contype AS constraint_type,
    pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'auth.users'::regclass
ORDER BY conname;

-- 5. Ver columnas NOT NULL en auth.users
SELECT 
    '5_NOT_NULL_COLUMNS' AS step,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'auth' 
  AND table_name = 'users'
  AND is_nullable = 'NO'
  AND column_default IS NULL  -- Sin default = requiere valor explícito
ORDER BY ordinal_position;
