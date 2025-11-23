-- =====================================================
-- 🔍 DIAGNÓSTICO SIMPLE: Ver triggers y código
-- =====================================================

-- 1️⃣ TRIGGERS EN auth.users
SELECT 
  '1_TRIGGERS' as step,
  tgname as trigger_name,
  proname as function_name,
  pg_get_triggerdef(pg_trigger.oid) as trigger_definition
FROM pg_trigger
JOIN pg_class ON pg_trigger.tgrelid = pg_class.oid
JOIN pg_namespace ON pg_class.relnamespace = pg_namespace.oid
JOIN pg_proc ON pg_trigger.tgfoid = pg_proc.oid
WHERE pg_namespace.nspname = 'auth'
  AND pg_class.relname = 'users'
ORDER BY tgname;

-- Separador visual
SELECT '================================================' as separator;

-- 2️⃣ CÓDIGO DE LA FUNCIÓN handle_new_user
SELECT 
  '2_FUNCTION_CODE' as step,
  proname as function_name,
  pg_get_functiondef(pg_proc.oid) as function_source
FROM pg_proc
JOIN pg_namespace ON pg_proc.pronamespace = pg_namespace.oid
WHERE proname = 'handle_new_user'
  AND pg_namespace.nspname = 'public'
LIMIT 1;

-- Separador visual
SELECT '================================================' as separator;

-- 3️⃣ CÓDIGO DE ensure_client_profile_and_account
SELECT 
  '3_ENSURE_CLIENT_FUNCTION' as step,
  proname as function_name,
  pg_get_functiondef(pg_proc.oid) as function_source
FROM pg_proc
JOIN pg_namespace ON pg_proc.pronamespace = pg_namespace.oid
WHERE proname = 'ensure_client_profile_and_account'
  AND pg_namespace.nspname = 'public'
LIMIT 1;

-- Separador visual
SELECT '================================================' as separator;

-- 4️⃣ COLUMNAS DE client_profiles
SELECT 
  '4_CLIENT_PROFILES_COLUMNS' as step,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'client_profiles'
ORDER BY ordinal_position;
