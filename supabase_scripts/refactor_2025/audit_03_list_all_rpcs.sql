-- =====================================================================
-- AUDITORÍA FASE 1.3: INVENTARIO DE RPCs ACCESIBLES DESDE FLUTTER
-- =====================================================================
-- Descripción:
--   Lista TODAS las funciones públicas que pueden ser llamadas como RPC
--   desde Flutter (schema public) relacionadas con signup/profiles
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
  'RPC_INVENTORY' AS step,
  p.proname AS rpc_name,
  pg_get_function_arguments(p.oid) AS parameters,
  pg_get_function_result(p.oid) AS return_type,
  CASE
    WHEN p.prosecdef THEN 'SECURITY DEFINER'
    ELSE 'SECURITY INVOKER'
  END AS security_mode,
  pg_get_functiondef(p.oid) AS function_source
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE
  n.nspname = 'public'
  AND (
    -- RPCs relacionados con signup/profiles
    p.proname ILIKE '%signup%'
    OR p.proname ILIKE '%register%'
    OR p.proname ILIKE '%profile%'
    OR p.proname ILIKE '%user%'
    OR p.proname ILIKE '%create%'
    OR p.proname ILIKE '%ensure%'
    -- Buscar en el código fuente
    OR pg_get_functiondef(p.oid) ILIKE '%auth.users%'
    OR pg_get_functiondef(p.oid) ILIKE '%client_profiles%'
    OR pg_get_functiondef(p.oid) ILIKE '%delivery_agent_profiles%'
    OR pg_get_functiondef(p.oid) ILIKE '%restaurants%'
  )
ORDER BY
  p.proname;

-- =====================================================================
-- PASO 2: VERIFICAR PERMISOS DE EJECUCIÓN
-- =====================================================================

SELECT
  'RPC_PERMISSIONS' AS step,
  n.nspname AS schema_name,
  p.proname AS rpc_name,
  pg_catalog.array_to_string(p.proacl, E'\n') AS acl_permissions,
  CASE
    WHEN pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE') THEN 'YES'
    ELSE 'NO'
  END AS anon_can_execute,
  CASE
    WHEN pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') THEN 'YES'
    ELSE 'NO'
  END AS authenticated_can_execute
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE
  n.nspname = 'public'
  AND (
    p.proname ILIKE '%signup%'
    OR p.proname ILIKE '%register%'
    OR p.proname ILIKE '%profile%'
    OR p.proname ILIKE '%user%'
    OR p.proname ILIKE '%create%'
    OR p.proname ILIKE '%ensure%'
  )
ORDER BY
  p.proname;

-- =====================================================================
-- RESULTADO ESPERADO:
-- - Lista de RPCs disponibles para signup/profiles
-- - Sus permisos de ejecución (anon, authenticated)
-- - Identificar RPCs obsoletos o redundantes
-- =====================================================================
