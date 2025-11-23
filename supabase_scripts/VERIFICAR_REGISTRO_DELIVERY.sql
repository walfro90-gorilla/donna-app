-- =============================================================
-- VERIFICACIÓN: Registro de Delivery Agent
-- =============================================================
-- Este script verifica que el RPC register_delivery_agent_atomic
-- existe y tiene los permisos correctos
-- =============================================================

-- 1. Verificar que el RPC existe
SELECT 
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as parameters,
  p.prosecdef as is_security_definer,
  CASE 
    WHEN p.prosecdef THEN '✅ SECURITY DEFINER enabled'
    ELSE '❌ SECURITY DEFINER missing'
  END as security_status
FROM pg_proc p 
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' 
  AND p.proname = 'register_delivery_agent_atomic';

-- 2. Verificar permisos del RPC
SELECT 
  p.proname as function_name,
  pg_catalog.pg_get_function_arguments(p.oid) as full_signature,
  CASE 
    WHEN has_function_privilege('anon', p.oid, 'EXECUTE') THEN '✅ anon can execute'
    ELSE '❌ anon cannot execute'
  END as anon_permission,
  CASE 
    WHEN has_function_privilege('authenticated', p.oid, 'EXECUTE') THEN '✅ authenticated can execute'
    ELSE '❌ authenticated cannot execute'
  END as authenticated_permission
FROM pg_proc p 
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' 
  AND p.proname = 'register_delivery_agent_atomic';

-- 3. Verificar que la función ensure_user_profile_public existe
SELECT 
  p.proname as dependency_function,
  CASE 
    WHEN p.proname IS NOT NULL THEN '✅ ensure_user_profile_public exists'
    ELSE '❌ ensure_user_profile_public missing'
  END as status
FROM pg_proc p 
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' 
  AND p.proname = 'ensure_user_profile_public';

-- 4. Verificar estructura de delivery_agent_profiles
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'delivery_agent_profiles'
ORDER BY ordinal_position;

-- 5. Verificar constraint único en accounts
SELECT 
  conname as constraint_name,
  pg_get_constraintdef(oid) as constraint_definition
FROM pg_constraint
WHERE conrelid = 'public.accounts'::regclass
  AND contype = 'u'
  AND conname LIKE '%user_id%account_type%';

-- 6. Verificar RPC antiguos (deben estar eliminados)
SELECT 
  p.proname as old_function_name,
  CASE 
    WHEN p.proname IS NOT NULL THEN '⚠️ Old RPC still exists - should be dropped'
    ELSE '✅ No old RPCs found'
  END as status
FROM pg_proc p 
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' 
  AND p.proname IN ('register_delivery_agent_v2');
