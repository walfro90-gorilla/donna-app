-- ============================================
-- 🔍 AUDITORÍA COMPLETA - TRIGGER Y RPC
-- ============================================
-- PROPÓSITO:
--   - Ver el código actual del TRIGGER handle_new_user_signup_v2()
--   - Ver el código actual del RPC ensure_user_profile_public()
--   - Identificar cualquier otro trigger que pueda interferir
--   - Verificar que las tablas tienen las columnas correctas
-- 
-- INSTRUCCIONES:
--   1. Copia y pega este script en el SQL Editor de Supabase
--   2. Ejecuta el script completo
--   3. Copia TODO el output y envíalo para análisis
-- ============================================

\echo ''
\echo '========================================'
\echo '🔍 AUDITORÍA: TRIGGER Y RPC PARA CLIENT'
\echo '========================================'
\echo ''

-- ============================================
-- 1. VERIFICAR ESTRUCTURA DE TABLAS
-- ============================================
\echo '📊 1. ESTRUCTURA DE TABLAS'
\echo '-----------------------------------'

\echo '✅ Columnas de public.users:'
SELECT 
  column_name, 
  data_type, 
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'users'
ORDER BY ordinal_position;

\echo ''
\echo '✅ Columnas de public.client_profiles:'
SELECT 
  column_name, 
  data_type, 
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'client_profiles'
ORDER BY ordinal_position;

\echo ''
\echo '✅ Columnas de public.accounts:'
SELECT 
  column_name, 
  data_type, 
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'accounts'
ORDER BY ordinal_position;

-- ============================================
-- 2. LISTAR TODOS LOS TRIGGERS EN auth.users
-- ============================================
\echo ''
\echo '📌 2. TRIGGERS EN auth.users'
\echo '-----------------------------------'

SELECT 
  trigger_name,
  event_manipulation,
  event_object_table,
  action_timing,
  action_orientation
FROM information_schema.triggers
WHERE event_object_schema = 'auth'
  AND event_object_table = 'users'
ORDER BY trigger_name;

-- ============================================
-- 3. VER CÓDIGO DEL TRIGGER handle_new_user_signup_v2
-- ============================================
\echo ''
\echo '🔧 3. CÓDIGO DEL TRIGGER handle_new_user_signup_v2()'
\echo '-----------------------------------'

SELECT 
  pg_get_functiondef(oid) as function_definition
FROM pg_proc 
WHERE proname = 'handle_new_user_signup_v2';

-- Si no existe con ese nombre, buscar variaciones
\echo ''
\echo '🔍 Buscando variaciones del nombre del trigger...'
SELECT 
  proname as function_name,
  pg_get_functiondef(oid) as function_definition
FROM pg_proc 
WHERE proname LIKE '%handle_new_user%'
  OR proname LIKE '%signup%'
ORDER BY proname;

-- ============================================
-- 4. VER CÓDIGO DEL RPC ensure_user_profile_public
-- ============================================
\echo ''
\echo '🔧 4. CÓDIGO DEL RPC ensure_user_profile_public()'
\echo '-----------------------------------'

SELECT 
  pg_get_functiondef(oid) as function_definition
FROM pg_proc 
WHERE proname = 'ensure_user_profile_public';

-- ============================================
-- 5. VERIFICAR OTROS RPCS RELACIONADOS
-- ============================================
\echo ''
\echo '🔍 5. OTROS RPCs RELACIONADOS CON USER PROFILE'
\echo '-----------------------------------'

SELECT 
  proname as function_name,
  pronargs as num_arguments,
  proargnames as argument_names
FROM pg_proc 
WHERE proname LIKE '%user_profile%'
  OR proname LIKE '%create_user%'
  OR proname LIKE '%ensure_user%'
ORDER BY proname;

-- ============================================
-- 6. VERIFICAR ÚLTIMOS REGISTROS DE CLIENTE
-- ============================================
\echo ''
\echo '👤 6. ÚLTIMOS 3 CLIENTES REGISTRADOS'
\echo '-----------------------------------'

\echo 'Datos en public.users:'
SELECT 
  id,
  email,
  name,
  phone,
  address,
  role,
  created_at
FROM public.users
WHERE role = 'client'
ORDER BY created_at DESC
LIMIT 3;

\echo ''
\echo 'Datos en public.client_profiles:'
SELECT 
  cp.user_id,
  u.email,
  cp.address,
  cp.lat,
  cp.lon,
  cp.address_structured,
  cp.created_at
FROM public.client_profiles cp
JOIN public.users u ON u.id = cp.user_id
ORDER BY cp.created_at DESC
LIMIT 3;

-- ============================================
-- 7. VERIFICAR auth.users metadata
-- ============================================
\echo ''
\echo '🔐 7. METADATA EN auth.users (ÚLTIMOS 3 CLIENTES)'
\echo '-----------------------------------'

SELECT 
  au.id,
  au.email,
  au.raw_user_meta_data,
  au.created_at
FROM auth.users au
JOIN public.users pu ON pu.id = au.id
WHERE pu.role = 'client'
ORDER BY au.created_at DESC
LIMIT 3;

-- ============================================
-- 8. VERIFICAR PERMISOS DE FUNCIONES
-- ============================================
\echo ''
\echo '🔒 8. PERMISOS DE ensure_user_profile_public'
\echo '-----------------------------------'

SELECT 
  grantee,
  privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name = 'ensure_user_profile_public';

-- ============================================
-- FIN DE AUDITORÍA
-- ============================================
\echo ''
\echo '========================================'
\echo '✅ AUDITORÍA COMPLETADA'
\echo '========================================'
\echo ''
\echo '📋 PRÓXIMOS PASOS:'
\echo '   1. Copia TODO el output de arriba'
\echo '   2. Envíalo para análisis'
\echo '   3. Identificaremos el problema exacto'
\echo '   4. Crearemos el script de reparación quirúrgica'
\echo ''
