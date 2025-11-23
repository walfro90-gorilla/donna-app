-- =====================================================================
-- AUDITORÍA FASE 1.1: INVENTARIO DE FUNCIONES RELACIONADAS CON SIGNUP
-- =====================================================================
-- Descripción:
--   Lista TODAS las funciones en public/auth que contienen palabras clave
--   relacionadas con signup, user creation, profiles, etc.
--
-- Esquema base:
--   - public.users (id references auth.users.id)
--   - public.client_profiles (user_id references users.id)
--   - public.delivery_agent_profiles (user_id references users.id)
--   - public.restaurants (user_id references users.id)
--
-- Uso:
--   Ejecutar en SQL Editor de Supabase
--   Copiar el resultado completo (especialmente 'function_source')
-- =====================================================================

SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_functiondef(p.oid) AS function_source,
  CASE
    WHEN p.provolatile = 'i' THEN 'IMMUTABLE'
    WHEN p.provolatile = 's' THEN 'STABLE'
    WHEN p.provolatile = 'v' THEN 'VOLATILE'
  END AS volatility,
  pg_get_function_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS return_type
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE
  n.nspname IN ('public', 'auth')
  AND (
    -- Buscar funciones relacionadas con signup/user creation
    p.proname ILIKE '%user%'
    OR p.proname ILIKE '%signup%'
    OR p.proname ILIKE '%profile%'
    OR p.proname ILIKE '%client%'
    OR p.proname ILIKE '%delivery%'
    OR p.proname ILIKE '%restaurant%'
    OR p.proname ILIKE '%handle%'
    OR p.proname ILIKE '%ensure%'
    OR p.proname ILIKE '%create%'
    OR p.proname ILIKE '%register%'
    OR pg_get_functiondef(p.oid) ILIKE '%auth.users%'
    OR pg_get_functiondef(p.oid) ILIKE '%public.users%'
    OR pg_get_functiondef(p.oid) ILIKE '%client_profiles%'
    OR pg_get_functiondef(p.oid) ILIKE '%delivery_agent_profiles%'
    OR pg_get_functiondef(p.oid) ILIKE '%restaurants%'
  )
ORDER BY
  n.nspname,
  p.proname;

-- =====================================================================
-- RESULTADO ESPERADO:
-- - Lista de funciones con su código fuente completo
-- - Identificar funciones obsoletas o redundantes
-- - Ver qué funciones manipulan users, client_profiles, delivery_agent_profiles, restaurants
-- =====================================================================
