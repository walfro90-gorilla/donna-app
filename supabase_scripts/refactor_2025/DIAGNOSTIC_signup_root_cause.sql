-- ======================================================================
-- 🔎 DIAGNÓSTICO SIGNUP 500: Encontrar la causa real en tu BD actual
-- Fuente de verdad: supabase_scripts/DATABASE_SCHEMA.sql (no ejecutar ese archivo)
-- Ejecuta este script en el SQL Editor de Supabase y comparte los resultados.
-- ======================================================================

-- 1) Definición actual en BD de ensure_client_profile_and_account()
SELECT 
  p.proname AS function_name,
  pg_get_functiondef(p.oid) AS function_definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'ensure_client_profile_and_account';

-- 2) Definición actual de handle_new_user() (trigger de signup)
SELECT 
  p.proname AS function_name,
  pg_get_functiondef(p.oid) AS function_definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'handle_new_user';

-- 3) Triggers activos sobre auth.users (qué función están llamando)
SELECT 
  t.tgname AS trigger_name,
  t.tgenabled AS enabled,
  pg_get_triggerdef(t.oid) AS trigger_definition
FROM pg_trigger t
WHERE t.tgrelid = 'auth.users'::regclass;

-- 4) Esquema actual de public.users (verifica NOT NULL y columnas reales)
SELECT 
  column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'users'
ORDER BY ordinal_position;

-- 5) Constraints de accounts.account_type (debe incluir 'client')
SELECT 
  conname AS constraint_name,
  pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
JOIN pg_class t ON c.conrelid = t.oid
JOIN pg_namespace n ON t.relnamespace = n.oid
WHERE n.nspname = 'public' AND t.relname = 'accounts' AND c.contype = 'c';

-- 6) Columnas reales de public.client_profiles (status debe existir)
SELECT 
  column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'client_profiles'
ORDER BY ordinal_position;

-- 7) Últimos logs de depuración si existen (opcional)
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema='public' AND table_name='debug_user_signup_log'
  ) THEN
    RAISE NOTICE '--- Últimos 25 debug_user_signup_log ---';
  END IF;
END $$;

-- Nota: después de un intento de registro, puedes inspeccionar logs con:
-- SELECT * FROM public.debug_user_signup_log ORDER BY created_at DESC LIMIT 50;

-- 8) (Opcional) Probar manualmente la función con un user_id existente en auth.users
-- Reemplaza '00000000-0000-0000-0000-000000000000' por un id real
-- SELECT public.ensure_client_profile_and_account('00000000-0000-0000-0000-000000000000');

-- ======================================================================
-- FIN DIAGNÓSTICO
-- ======================================================================
