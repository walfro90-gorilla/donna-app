-- ============================================================================
-- AUDITORÍA COMPLETA: FUNCIONES, TRIGGERS Y RPCS
-- ============================================================================
-- Este script es puramente informativo. 
-- Ejecútalo en Supabase y comparte los resultados (exporta a CSV o JSON si puedes).
-- ============================================================================

-- 1. LISTAR FUNCIONES (RPCs y Helpers)
-- Buscamos funciones en el esquema 'public' que no sean nativas de PostGIS.
SELECT 
    p.proname as function_name,
    pg_get_function_arguments(p.oid) as arguments,
    CASE 
        WHEN p.prosecdef THEN 'Security Definer (Bypass RLS)' 
        ELSE 'Invoker (Respeta RLS)' 
    END as security_type,
    obj_description(p.oid, 'pg_proc') as description
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
AND p.proname NOT LIKE 'st_%'         -- Ignorar PostGIS
AND p.proname NOT LIKE '_st_%'        -- Ignorar PostGIS internal
AND p.proname NOT LIKE 'geography_%'  -- Ignorar PostGIS types
AND p.proname NOT LIKE 'geometry_%'   -- Ignorar PostGIS types
ORDER BY p.proname;

-- 2. LISTAR TRIGGERS ACTIVOS
-- Muestra qué disparadores se ejecutan y en qué tablas.
SELECT 
    event_object_table as table_name,
    trigger_name,
    event_manipulation as event,
    action_timing as timing,
    action_statement as function_call
FROM information_schema.triggers
WHERE event_object_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- 3. LISTAR POLÍTICAS RLS (Row Level Security)
-- Fundamental para saber quién puede ver qué.
SELECT 
    tablename,
    policyname,
    roles,
    cmd as action,
    qual as definition_using,
    with_check as definition_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;
