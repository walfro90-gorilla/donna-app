-- ============================================================
-- AUDITORÍA DE REGISTRO DE CLIENTE - APEGADO AL SCHEMA REAL
-- ============================================================
-- Este script SOLO consulta datos existentes
-- Compatible con Supabase SQL Runner
-- Basado en DATABASE_SCHEMA.SQL
-- ============================================================

-- ============================================================
-- PARTE 1: VERIFICAR ESTRUCTURA DE TABLAS INVOLUCRADAS
-- ============================================================

-- 1.1 Verificar columnas de public.users
SELECT 
  'TABLA: public.users' as seccion,
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'users'
ORDER BY ordinal_position;

-- 1.2 Verificar columnas de public.client_profiles
SELECT 
  'TABLA: public.client_profiles' as seccion,
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'client_profiles'
ORDER BY ordinal_position;

-- 1.3 Verificar columnas de public.user_preferences
SELECT 
  'TABLA: public.user_preferences' as seccion,
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'user_preferences'
ORDER BY ordinal_position;

-- ============================================================
-- PARTE 2: VERIFICAR ÚLTIMO REGISTRO DE CLIENTE
-- ============================================================

-- 2.1 Ver último cliente registrado en public.users
SELECT 
  'ÚLTIMO CLIENTE EN USERS' as seccion,
  id,
  email,
  name,
  phone,
  role,
  created_at,
  updated_at,
  email_confirm
FROM public.users
WHERE role = 'client'
ORDER BY created_at DESC
LIMIT 3;

-- 2.2 Ver datos del último cliente en public.client_profiles
SELECT 
  'ÚLTIMO CLIENTE EN CLIENT_PROFILES' as seccion,
  cp.user_id,
  u.email,
  u.name,
  cp.address,
  cp.lat,
  cp.lon,
  cp.address_structured,
  cp.status,
  cp.created_at
FROM public.client_profiles cp
LEFT JOIN public.users u ON u.id = cp.user_id
WHERE u.role = 'client'
ORDER BY cp.created_at DESC
LIMIT 3;

-- 2.3 Ver datos del último cliente en public.user_preferences
SELECT 
  'ÚLTIMO CLIENTE EN USER_PREFERENCES' as seccion,
  up.user_id,
  u.email,
  u.name,
  up.has_seen_onboarding,
  up.login_count,
  up.first_login_at,
  up.last_login_at,
  up.created_at
FROM public.user_preferences up
LEFT JOIN public.users u ON u.id = up.user_id
WHERE u.role = 'client'
ORDER BY up.created_at DESC
LIMIT 3;

-- ============================================================
-- PARTE 3: BUSCAR CLIENTES CON DATOS INCOMPLETOS
-- ============================================================

-- 3.1 Clientes SIN nombre o teléfono en public.users
SELECT 
  'CLIENTES SIN NOMBRE/TELÉFONO' as problema,
  id,
  email,
  name,
  phone,
  created_at
FROM public.users
WHERE role = 'client'
  AND (name IS NULL OR phone IS NULL)
ORDER BY created_at DESC
LIMIT 5;

-- 3.2 Clientes SIN registro en client_profiles
SELECT 
  'CLIENTES SIN PERFIL' as problema,
  u.id,
  u.email,
  u.name,
  u.created_at
FROM public.users u
LEFT JOIN public.client_profiles cp ON cp.user_id = u.id
WHERE u.role = 'client'
  AND cp.user_id IS NULL
ORDER BY u.created_at DESC
LIMIT 5;

-- 3.3 Clientes CON perfil pero SIN ubicación
SELECT 
  'CLIENTES SIN UBICACIÓN' as problema,
  u.id,
  u.email,
  u.name,
  cp.lat,
  cp.lon,
  cp.address,
  cp.created_at
FROM public.client_profiles cp
JOIN public.users u ON u.id = cp.user_id
WHERE u.role = 'client'
  AND (cp.lat IS NULL OR cp.lon IS NULL)
ORDER BY cp.created_at DESC
LIMIT 5;

-- ============================================================
-- PARTE 4: VERIFICAR FUNCIONES Y TRIGGERS
-- ============================================================

-- 4.1 Listar todas las funciones relacionadas con 'user'
SELECT 
  'FUNCIONES DE USUARIO' as seccion,
  proname as function_name,
  pg_get_function_arguments(oid) as arguments,
  prosrc as source_code
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname LIKE '%user%'
ORDER BY proname;

-- 4.2 Listar triggers en la tabla public.users
SELECT 
  'TRIGGERS EN PUBLIC.USERS' as seccion,
  tgname as trigger_name,
  tgtype as trigger_type,
  tgenabled as is_enabled,
  pg_get_triggerdef(oid) as trigger_definition
FROM pg_trigger
WHERE tgrelid = 'public.users'::regclass
  AND tgisinternal = false;

-- 4.3 Listar triggers en la tabla public.client_profiles
SELECT 
  'TRIGGERS EN PUBLIC.CLIENT_PROFILES' as seccion,
  tgname as trigger_name,
  tgtype as trigger_type,
  tgenabled as is_enabled,
  pg_get_triggerdef(oid) as trigger_definition
FROM pg_trigger
WHERE tgrelid = 'public.client_profiles'::regclass
  AND tgisinternal = false;

-- ============================================================
-- PARTE 5: VERIFICAR LOGS DE DEBUG (si existen registros)
-- ============================================================

-- 5.1 Ver últimos logs de debug_user_signup_log
SELECT 
  'DEBUG SIGNUP LOG' as seccion,
  id,
  source,
  event,
  role,
  user_id,
  email,
  details,
  created_at
FROM public.debug_user_signup_log
ORDER BY created_at DESC
LIMIT 10;

-- 5.2 Ver últimos logs de function_logs relacionados con signup
SELECT 
  'FUNCTION LOGS' as seccion,
  id,
  function_name,
  message,
  metadata,
  level,
  created_at
FROM public.function_logs
WHERE function_name LIKE '%user%' 
   OR function_name LIKE '%profile%'
   OR message LIKE '%client%'
ORDER BY created_at DESC
LIMIT 10;

-- ============================================================
-- FIN DE AUDITORÍA
-- ============================================================
-- PRÓXIMOS PASOS:
-- 1. Revisar los resultados de PARTE 3 para identificar registros incompletos
-- 2. Revisar PARTE 4 para ver qué triggers/funciones están activos
-- 3. Revisar PARTE 5 para ver logs de errores durante signup
-- ============================================================
