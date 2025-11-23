-- =====================================================
-- SCRIPT DE VERIFICACIÓN: Tablas requeridas
-- =====================================================
-- Este script verifica que todas las tablas necesarias
-- para las funciones de registro existen
-- =====================================================

SELECT 
  '🔍 VERIFICANDO TABLAS REQUERIDAS' as etapa;

-- ====================================
-- Verificar tablas principales
-- ====================================

SELECT 
  table_name,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_name = t.table_name
    ) THEN '✅ Existe'
    ELSE '❌ NO EXISTE'
  END as status
FROM (
  VALUES 
    ('users'),
    ('client_profiles'),
    ('restaurants'),
    ('delivery_agent_profiles'),
    ('accounts'),
    ('user_preferences'),
    ('admin_notifications'),
    ('debug_logs')
) AS t(table_name)
ORDER BY table_name;

-- ====================================
-- Verificar columnas críticas en public.users
-- ====================================

SELECT 
  '🔍 VERIFICANDO COLUMNAS EN public.users' as etapa;

SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'users'
  AND column_name IN ('id', 'email', 'name', 'phone', 'role', 'email_confirm', 'created_at', 'updated_at')
ORDER BY column_name;

-- ====================================
-- Verificar columnas en client_profiles
-- ====================================

SELECT 
  '🔍 VERIFICANDO COLUMNAS EN client_profiles' as etapa;

SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'client_profiles'
  AND column_name IN ('user_id', 'address', 'lat', 'lon', 'address_structured', 'created_at', 'updated_at')
ORDER BY column_name;

-- ====================================
-- Verificar columnas en restaurants
-- ====================================

SELECT 
  '🔍 VERIFICANDO COLUMNAS EN restaurants' as etapa;

SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'restaurants'
  AND column_name IN ('id', 'user_id', 'name', 'description', 'status', 'address', 'phone', 'online', 'created_at', 'updated_at')
ORDER BY column_name;

-- ====================================
-- Verificar columnas en delivery_agent_profiles
-- ====================================

SELECT 
  '🔍 VERIFICANDO COLUMNAS EN delivery_agent_profiles' as etapa;

SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'delivery_agent_profiles'
  AND column_name IN ('user_id', 'vehicle_type', 'status', 'account_state', 'onboarding_completed', 'created_at', 'updated_at')
ORDER BY column_name;

-- ====================================
-- Verificar columnas en accounts
-- ====================================

SELECT 
  '🔍 VERIFICANDO COLUMNAS EN accounts' as etapa;

SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'accounts'
  AND column_name IN ('id', 'user_id', 'account_type', 'balance', 'created_at', 'updated_at')
ORDER BY column_name;

-- ====================================
-- Verificar tipos ENUM necesarios
-- ====================================

SELECT 
  '🔍 VERIFICANDO TIPOS ENUM' as etapa;

SELECT 
  t.typname as enum_name,
  STRING_AGG(e.enumlabel, ', ' ORDER BY e.enumsortorder) as valores
FROM pg_type t 
JOIN pg_enum e ON t.oid = e.enumtypid  
JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'public'
  AND t.typname IN ('user_role', 'restaurant_status', 'delivery_agent_status', 'delivery_agent_account_state', 'account_type')
GROUP BY t.typname
ORDER BY t.typname;

-- ====================================
-- Verificar función auth.sign_up_v2 existe
-- ====================================

SELECT 
  '🔍 VERIFICANDO FUNCIÓN auth.sign_up_v2' as etapa;

SELECT 
  p.proname as function_name,
  pg_catalog.pg_get_function_arguments(p.oid) as arguments,
  CASE 
    WHEN p.proname = 'sign_up_v2' THEN '✅ Existe'
    ELSE '❌ NO EXISTE'
  END as status
FROM pg_catalog.pg_proc p
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'auth'
  AND p.proname = 'sign_up_v2';

-- ====================================
-- RESUMEN FINAL
-- ====================================

SELECT 
  '📋 RESUMEN' as etapa,
  'Si todas las tablas y columnas existen, puedes proceder a crear las funciones de registro.' as resultado;
