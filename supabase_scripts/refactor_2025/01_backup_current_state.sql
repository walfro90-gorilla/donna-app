-- =====================================================
-- FASE 1: BACKUP DEL ESTADO ACTUAL
-- =====================================================
-- Ejecutar PRIMERO antes de cualquier cambio
-- Tiempo estimado: 5 minutos
-- =====================================================

BEGIN;

-- Crear schema temporal para backups si no existe
CREATE SCHEMA IF NOT EXISTS backup_refactor_2025;

-- Backup de tablas críticas
CREATE TABLE backup_refactor_2025.users_backup AS 
SELECT * FROM public.users;

CREATE TABLE backup_refactor_2025.client_profiles_backup AS 
SELECT * FROM public.client_profiles;

CREATE TABLE backup_refactor_2025.restaurants_backup AS 
SELECT * FROM public.restaurants;

CREATE TABLE backup_refactor_2025.delivery_agent_profiles_backup AS 
SELECT * FROM public.delivery_agent_profiles;

CREATE TABLE backup_refactor_2025.accounts_backup AS 
SELECT * FROM public.accounts;

CREATE TABLE backup_refactor_2025.user_preferences_backup AS 
SELECT * FROM public.user_preferences;

-- Backup de constraints importantes
CREATE TABLE backup_refactor_2025.constraints_backup AS
SELECT 
  conname AS constraint_name,
  conrelid::regclass AS table_name,
  pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
  AND conrelid::regclass::text IN ('users', 'client_profiles', 'restaurants', 'delivery_agent_profiles');

-- Log de backup
INSERT INTO public.debug_logs (scope, message, meta)
VALUES (
  'REFACTOR_2025_BACKUP',
  'Backup completado exitosamente',
  jsonb_build_object(
    'timestamp', NOW(),
    'users_count', (SELECT COUNT(*) FROM public.users),
    'clients_count', (SELECT COUNT(*) FROM public.client_profiles),
    'restaurants_count', (SELECT COUNT(*) FROM public.restaurants),
    'delivery_agents_count', (SELECT COUNT(*) FROM public.delivery_agent_profiles)
  )
);

COMMIT;

-- Verificación
SELECT 
  'users_backup' AS tabla,
  COUNT(*) AS registros
FROM backup_refactor_2025.users_backup
UNION ALL
SELECT 
  'client_profiles_backup',
  COUNT(*)
FROM backup_refactor_2025.client_profiles_backup
UNION ALL
SELECT 
  'restaurants_backup',
  COUNT(*)
FROM backup_refactor_2025.restaurants_backup
UNION ALL
SELECT 
  'delivery_agent_profiles_backup',
  COUNT(*)
FROM backup_refactor_2025.delivery_agent_profiles_backup;

-- ✅ Si ves registros aquí, el backup fue exitoso
