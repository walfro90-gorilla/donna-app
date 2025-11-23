-- ============================================================================
-- FASE 1 - SCRIPT 01: BACKUP DE FUNCIONES OBSOLETAS
-- ============================================================================
-- Descripción: Crea una tabla de backup y guarda el código fuente de todas
--              las funciones obsoletas antes de eliminarlas.
-- ============================================================================

-- Crear tabla de backup si no existe
CREATE TABLE IF NOT EXISTS public._backup_obsolete_functions (
  id bigserial PRIMARY KEY,
  function_schema text NOT NULL,
  function_name text NOT NULL,
  function_args text,
  function_source text NOT NULL,
  function_type text, -- 'function', 'trigger', 'rpc'
  reason_obsolete text,
  backed_up_at timestamptz DEFAULT now()
);

COMMENT ON TABLE public._backup_obsolete_functions IS 
  'Backup de funciones obsoletas antes de la refactorización de signup';

-- ============================================================================
-- BACKUP DE FUNCIONES OBSOLETAS (13+ funciones)
-- ============================================================================

-- 1. register_client
INSERT INTO public._backup_obsolete_functions (function_schema, function_name, function_args, function_source, function_type, reason_obsolete)
SELECT 
  'public', 
  'register_client',
  pg_get_function_arguments(oid),
  pg_get_functiondef(oid),
  'rpc',
  'Redundante - el signup debe ser automático vía trigger en auth.users'
FROM pg_proc 
WHERE proname = 'register_client' AND pronamespace = 'public'::regnamespace
ON CONFLICT DO NOTHING;

-- 2. register_delivery_agent
INSERT INTO public._backup_obsolete_functions (function_schema, function_name, function_args, function_source, function_type, reason_obsolete)
SELECT 
  'public', 
  'register_delivery_agent',
  pg_get_function_arguments(oid),
  pg_get_functiondef(oid),
  'rpc',
  'Redundante - el signup debe ser automático vía trigger en auth.users'
FROM pg_proc 
WHERE proname = 'register_delivery_agent' AND pronamespace = 'public'::regnamespace
ON CONFLICT DO NOTHING;

-- 3. register_delivery_agent_atomic
INSERT INTO public._backup_obsolete_functions (function_schema, function_name, function_args, function_source, function_type, reason_obsolete)
SELECT 
  'public', 
  'register_delivery_agent_atomic',
  pg_get_function_arguments(oid),
  pg_get_functiondef(oid),
  'rpc',
  'Redundante - el signup debe ser automático vía trigger en auth.users'
FROM pg_proc 
WHERE proname = 'register_delivery_agent_atomic' AND pronamespace = 'public'::regnamespace
ON CONFLICT DO NOTHING;

-- 4. register_restaurant
INSERT INTO public._backup_obsolete_functions (function_schema, function_name, function_args, function_source, function_type, reason_obsolete)
SELECT 
  'public', 
  'register_restaurant',
  pg_get_function_arguments(oid),
  pg_get_functiondef(oid),
  'rpc',
  'Redundante - el signup debe ser automático vía trigger en auth.users'
FROM pg_proc 
WHERE proname = 'register_restaurant' AND pronamespace = 'public'::regnamespace
ON CONFLICT DO NOTHING;

-- 5. register_restaurant_v2
INSERT INTO public._backup_obsolete_functions (function_schema, function_name, function_args, function_source, function_type, reason_obsolete)
SELECT 
  'public', 
  'register_restaurant_v2',
  pg_get_function_arguments(oid),
  pg_get_functiondef(oid),
  'rpc',
  'Redundante - el signup debe ser automático vía trigger en auth.users'
FROM pg_proc 
WHERE proname = 'register_restaurant_v2' AND pronamespace = 'public'::regnamespace
ON CONFLICT DO NOTHING;

-- 6. create_user_profile_public
INSERT INTO public._backup_obsolete_functions (function_schema, function_name, function_args, function_source, function_type, reason_obsolete)
SELECT 
  'public', 
  'create_user_profile_public',
  pg_get_function_arguments(oid),
  pg_get_functiondef(oid),
  'rpc',
  'Redundante - el signup debe ser automático vía trigger en auth.users'
FROM pg_proc 
WHERE proname = 'create_user_profile_public' AND pronamespace = 'public'::regnamespace
ON CONFLICT DO NOTHING;

-- 7. create_delivery_agent
INSERT INTO public._backup_obsolete_functions (function_schema, function_name, function_args, function_source, function_type, reason_obsolete)
SELECT 
  'public', 
  'create_delivery_agent',
  pg_get_function_arguments(oid),
  pg_get_functiondef(oid),
  'rpc',
  'Redundante - el signup debe ser automático vía trigger en auth.users'
FROM pg_proc 
WHERE proname = 'create_delivery_agent' AND pronamespace = 'public'::regnamespace
ON CONFLICT DO NOTHING;

-- 8. create_restaurant_public
INSERT INTO public._backup_obsolete_functions (function_schema, function_name, function_args, function_source, function_type, reason_obsolete)
SELECT 
  'public', 
  'create_restaurant_public',
  pg_get_function_arguments(oid),
  pg_get_functiondef(oid),
  'rpc',
  'Redundante - el signup debe ser automático vía trigger en auth.users'
FROM pg_proc 
WHERE proname = 'create_restaurant_public' AND pronamespace = 'public'::regnamespace
ON CONFLICT DO NOTHING;

-- 9. ensure_user_profile_public
INSERT INTO public._backup_obsolete_functions (function_schema, function_name, function_args, function_source, function_type, reason_obsolete)
SELECT 
  'public', 
  'ensure_user_profile_public',
  pg_get_function_arguments(oid),
  pg_get_functiondef(oid),
  'rpc',
  'Redundante - el signup debe ser automático vía trigger en auth.users'
FROM pg_proc 
WHERE proname = 'ensure_user_profile_public' AND pronamespace = 'public'::regnamespace
ON CONFLICT DO NOTHING;

-- 10. ensure_user_profile_v2
INSERT INTO public._backup_obsolete_functions (function_schema, function_name, function_args, function_source, function_type, reason_obsolete)
SELECT 
  'public', 
  'ensure_user_profile_v2',
  pg_get_function_arguments(oid),
  pg_get_functiondef(oid),
  'rpc',
  'Redundante - el signup debe ser automático vía trigger en auth.users'
FROM pg_proc 
WHERE proname = 'ensure_user_profile_v2' AND pronamespace = 'public'::regnamespace
ON CONFLICT DO NOTHING;

-- 11. ensure_client_profile_and_account
INSERT INTO public._backup_obsolete_functions (function_schema, function_name, function_args, function_source, function_type, reason_obsolete)
SELECT 
  'public', 
  'ensure_client_profile_and_account',
  pg_get_function_arguments(oid),
  pg_get_functiondef(oid),
  'rpc',
  'Redundante - el signup debe ser automático vía trigger en auth.users'
FROM pg_proc 
WHERE proname = 'ensure_client_profile_and_account' AND pronamespace = 'public'::regnamespace
ON CONFLICT DO NOTHING;

-- 12. ensure_delivery_agent_role_and_profile
INSERT INTO public._backup_obsolete_functions (function_schema, function_name, function_args, function_source, function_type, reason_obsolete)
SELECT 
  'public', 
  'ensure_delivery_agent_role_and_profile',
  pg_get_function_arguments(oid),
  pg_get_functiondef(oid),
  'rpc',
  'Redundante - el signup debe ser automático vía trigger en auth.users'
FROM pg_proc 
WHERE proname = 'ensure_delivery_agent_role_and_profile' AND pronamespace = 'public'::regnamespace
ON CONFLICT DO NOTHING;

-- 13. ensure_my_delivery_profile
INSERT INTO public._backup_obsolete_functions (function_schema, function_name, function_args, function_source, function_type, reason_obsolete)
SELECT 
  'public', 
  'ensure_my_delivery_profile',
  pg_get_function_arguments(oid),
  pg_get_functiondef(oid),
  'rpc',
  'Redundante - el signup debe ser automático vía trigger en auth.users'
FROM pg_proc 
WHERE proname = 'ensure_my_delivery_profile' AND pronamespace = 'public'::regnamespace
ON CONFLICT DO NOTHING;

-- ============================================================================
-- BACKUP DE FUNCIÓN ACTUAL (handle_new_user) - ANTES DE REEMPLAZARLA
-- ============================================================================

INSERT INTO public._backup_obsolete_functions (function_schema, function_name, function_args, function_source, function_type, reason_obsolete)
SELECT 
  'public', 
  'handle_new_user',
  pg_get_function_arguments(oid),
  pg_get_functiondef(oid),
  'trigger',
  'Se reemplaza por master_handle_signup() - versión anterior asumía que todos eran clientes'
FROM pg_proc 
WHERE proname = 'handle_new_user' AND pronamespace = 'public'::regnamespace
ON CONFLICT DO NOTHING;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

DO $$
DECLARE
  v_backup_count INT;
BEGIN
  SELECT COUNT(*) INTO v_backup_count FROM public._backup_obsolete_functions;
  
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ BACKUP COMPLETADO';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Total de funciones respaldadas: %', v_backup_count;
  RAISE NOTICE '';
  RAISE NOTICE '📋 Para ver el backup:';
  RAISE NOTICE 'SELECT function_name, reason_obsolete, backed_up_at FROM public._backup_obsolete_functions;';
  RAISE NOTICE '';
  RAISE NOTICE '✅ Puedes continuar con el script 02_cleanup_disable_triggers.sql';
END $$;
