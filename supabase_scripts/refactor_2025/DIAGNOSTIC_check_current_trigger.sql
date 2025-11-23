-- ===================================================================
-- 🔍 SCRIPT DE DIAGNÓSTICO - VERIFICAR TRIGGER Y FUNCIÓN ACTUAL
-- ===================================================================
-- Ejecuta este script para ver qué versión del trigger está activa
-- ===================================================================

-- 1️⃣ Ver definición actual de la función ensure_client_profile_and_account
SELECT 
  proname AS function_name,
  pg_get_functiondef(oid) AS function_definition
FROM pg_proc
WHERE proname = 'ensure_client_profile_and_account'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

-- 2️⃣ Ver definición actual de la función handle_new_user
SELECT 
  proname AS function_name,
  pg_get_functiondef(oid) AS function_definition
FROM pg_proc
WHERE proname = 'handle_new_user'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

-- 3️⃣ Ver trigger activo en auth.users
SELECT 
  tgname AS trigger_name,
  tgenabled AS enabled,
  pg_get_triggerdef(oid) AS trigger_definition
FROM pg_trigger
WHERE tgrelid = 'auth.users'::regclass
AND tgname = 'on_auth_user_created';

-- 4️⃣ Ver columnas actuales de client_profiles
SELECT 
  column_name,
  data_type,
  column_default,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name = 'client_profiles'
ORDER BY ordinal_position;
