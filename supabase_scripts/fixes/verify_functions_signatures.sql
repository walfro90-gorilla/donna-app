-- =====================================================
-- SCRIPT DE VERIFICACIÓN: Firmas de funciones reales
-- =====================================================
-- Este script consulta pg_proc para ver las firmas
-- exactas de las funciones de registro que existen
-- en la base de datos
-- =====================================================

-- Verificar función register_client
SELECT 
  'register_client' as function_name,
  p.proname,
  pg_catalog.pg_get_function_arguments(p.oid) as arguments,
  pg_catalog.pg_get_function_result(p.oid) as return_type,
  p.prosrc as source_code_preview
FROM pg_catalog.pg_proc p
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'register_client';

-- Verificar función register_restaurant
SELECT 
  'register_restaurant' as function_name,
  p.proname,
  pg_catalog.pg_get_function_arguments(p.oid) as arguments,
  pg_catalog.pg_get_function_result(p.oid) as return_type
FROM pg_catalog.pg_proc p
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'register_restaurant';

-- Verificar función register_delivery_agent
SELECT 
  'register_delivery_agent' as function_name,
  p.proname,
  pg_catalog.pg_get_function_arguments(p.oid) as arguments,
  pg_catalog.pg_get_function_result(p.oid) as return_type
FROM pg_catalog.pg_proc p
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'register_delivery_agent';

-- Ver todas las funciones públicas disponibles
SELECT 
  p.proname as function_name,
  pg_catalog.pg_get_function_arguments(p.oid) as arguments
FROM pg_catalog.pg_proc p
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname LIKE 'register%'
ORDER BY p.proname;
