-- =====================================================================
-- AUDITORÍA FASE 1.2: INVENTARIO DE TRIGGERS EN auth.users Y public.*
-- =====================================================================
-- Descripción:
--   Lista TODOS los triggers que se ejecutan en:
--   - auth.users (signup automático)
--   - public.users
--   - public.client_profiles
--   - public.delivery_agent_profiles
--   - public.restaurants
--
-- Esquema base según DATABASE_SCHEMA.sql:
--   - public.users (id references auth.users.id)
--   - public.client_profiles (user_id references users.id)
--   - public.delivery_agent_profiles (user_id references users.id)
--   - public.restaurants (user_id references users.id)
--
-- Uso:
--   Ejecutar en SQL Editor de Supabase
--   Copiar el resultado completo
-- =====================================================================

SELECT
  'TRIGGER_INVENTORY' AS step,
  n.nspname AS schema_name,
  c.relname AS table_name,
  t.tgname AS trigger_name,
  -- Cuándo se ejecuta
  CASE
    WHEN tgtype::int & 2 = 2 THEN 'BEFORE'
    WHEN tgtype::int & 64 = 64 THEN 'INSTEAD OF'
    ELSE 'AFTER'
  END AS trigger_timing,
  -- Qué evento lo activa
  CASE
    WHEN tgtype::int & 4 = 4 THEN 'INSERT'
    WHEN tgtype::int & 8 = 8 THEN 'DELETE'
    WHEN tgtype::int & 16 = 16 THEN 'UPDATE'
    ELSE 'UNKNOWN'
  END AS trigger_event,
  -- Función que ejecuta
  tgfoid::regproc AS trigger_function,
  -- Habilitado o no
  CASE
    WHEN tgenabled = 'O' THEN 'ENABLED'
    WHEN tgenabled = 'D' THEN 'DISABLED'
    WHEN tgenabled = 'R' THEN 'REPLICA'
    WHEN tgenabled = 'A' THEN 'ALWAYS'
    ELSE 'UNKNOWN'
  END AS trigger_status
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE
  n.nspname IN ('auth', 'public')
  AND c.relname IN (
    'users',
    'client_profiles',
    'delivery_agent_profiles',
    'restaurants'
  )
  AND NOT tgisinternal  -- Excluir triggers internos de constraints
ORDER BY
  n.nspname,
  c.relname,
  t.tgname;

-- =====================================================================
-- PASO 2: OBTENER EL CÓDIGO DE LAS FUNCIONES DE TRIGGER
-- =====================================================================

SELECT
  'TRIGGER_FUNCTION_CODE' AS step,
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_functiondef(p.oid) AS function_source
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE
  p.oid IN (
    SELECT DISTINCT tgfoid
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace ns ON c.relnamespace = ns.oid
    WHERE
      ns.nspname IN ('auth', 'public')
      AND c.relname IN ('users', 'client_profiles', 'delivery_agent_profiles', 'restaurants')
      AND NOT t.tgisinternal
  )
ORDER BY
  n.nspname,
  p.proname;

-- =====================================================================
-- RESULTADO ESPERADO:
-- - Lista de triggers activos en las tablas críticas
-- - Código fuente de las funciones que ejecutan
-- - Identificar triggers obsoletos o en conflicto
-- =====================================================================
