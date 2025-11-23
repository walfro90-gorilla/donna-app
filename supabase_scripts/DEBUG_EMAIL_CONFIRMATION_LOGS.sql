-- ============================================================================
-- DEBUG: Email Confirmation - Basado en DATABASE_SCHEMA.sql
-- ============================================================================
-- Ejecuta este script y COPIA TODO el output
-- ============================================================================

-- 1️⃣ Ver logs del trigger (tabla: trigger_debug_log)
SELECT 
  id,
  ts,
  function_name,
  user_id,
  event,
  details,
  error_message,
  stack_trace
FROM public.trigger_debug_log
WHERE function_name LIKE '%email%' 
   OR function_name LIKE '%confirm%'
   OR event LIKE '%email%'
   OR event LIKE '%confirm%'
ORDER BY ts DESC
LIMIT 20;

-- 2️⃣ Ver usuarios sin confirmar email (columna: email_confirm)
SELECT 
  u.id,
  u.email,
  u.name,
  u.role,
  u.email_confirm,
  u.created_at as public_created_at,
  au.email_confirmed_at as auth_confirmed_at,
  au.confirmed_at as auth_confirmed_at_legacy
FROM public.users u
LEFT JOIN auth.users au ON u.id = au.id
WHERE u.email_confirm = false
ORDER BY u.created_at DESC
LIMIT 10;

-- 3️⃣ Ver estado del trigger en auth.users
SELECT 
  trigger_name,
  event_manipulation as event,
  action_timing as timing,
  action_statement as function_call
FROM information_schema.triggers
WHERE event_object_table = 'users'
  AND event_object_schema = 'auth'
ORDER BY trigger_name;

-- 4️⃣ Políticas RLS de UPDATE en public.users
SELECT 
  policyname,
  roles,
  cmd,
  qual as condition,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'users'
  AND cmd = 'UPDATE'
ORDER BY policyname;

-- 5️⃣ Verificar si RLS está habilitado en public.users
SELECT 
  tablename,
  rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename = 'users';

-- 6️⃣ Últimos 5 usuarios creados en auth.users
SELECT 
  id,
  email,
  email_confirmed_at,
  confirmed_at,
  created_at,
  updated_at,
  last_sign_in_at
FROM auth.users
ORDER BY created_at DESC
LIMIT 5;

-- 7️⃣ Desincronización entre auth.users y public.users
SELECT 
  au.email,
  au.id as auth_user_id,
  au.email_confirmed_at as auth_confirmed,
  u.id as public_user_id,
  u.email_confirm as public_confirmed
FROM auth.users au
LEFT JOIN public.users u ON au.id = u.id
WHERE 
  (au.email_confirmed_at IS NOT NULL AND u.email_confirm = false)
  OR (au.email_confirmed_at IS NULL AND u.email_confirm = true)
ORDER BY au.created_at DESC
LIMIT 10;

-- 8️⃣ Ver función que maneja la confirmación de email
SELECT 
  proname as function_name,
  pg_get_functiondef(oid) as function_definition
FROM pg_proc
WHERE proname LIKE '%email%'
   OR proname LIKE '%confirm%'
ORDER BY proname;

-- ✅ MENSAJE FINAL
SELECT '✅ COPIA TODO EL OUTPUT ANTERIOR' AS resultado;
