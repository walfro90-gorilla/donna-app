-- =====================================================
-- SCRIPT DE DIAGNÓSTICO Y RE-CREACIÓN DE FUNCIONES
-- =====================================================
-- EJECUTA ESTE SCRIPT PRIMERO para diagnosticar el problema
-- y luego re-ejecutar los scripts 06, 07, 08
-- =====================================================

-- ====================================
-- PASO 1: VERIFICAR FUNCIONES EXISTENTES
-- ====================================

-- Ver todas las funciones de registro que existen actualmente
SELECT 
  '🔍 DIAGNÓSTICO: Funciones de registro existentes' as etapa;

SELECT 
  p.proname as function_name,
  pg_catalog.pg_get_function_arguments(p.oid) as arguments,
  pg_catalog.pg_get_function_result(p.oid) as return_type
FROM pg_catalog.pg_proc p
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname LIKE '%register%'
ORDER BY p.proname;

-- ====================================
-- PASO 2: ELIMINAR TODAS LAS VERSIONES ANTERIORES
-- ====================================

SELECT 
  '🧹 LIMPIEZA: Eliminando todas las versiones anteriores' as etapa;

-- Ejecutar limpieza de funciones ambiguas
DO $$
DECLARE
  r RECORD;
BEGIN
  -- Eliminar todas las versiones de register_client
  FOR r IN 
    SELECT oid::regprocedure as func_signature
    FROM pg_proc 
    WHERE proname = 'register_client' 
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.func_signature || ' CASCADE';
    RAISE NOTICE 'Eliminada función: %', r.func_signature;
  END LOOP;

  -- Eliminar todas las versiones de register_restaurant
  FOR r IN 
    SELECT oid::regprocedure as func_signature
    FROM pg_proc 
    WHERE proname = 'register_restaurant' 
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.func_signature || ' CASCADE';
    RAISE NOTICE 'Eliminada función: %', r.func_signature;
  END LOOP;

  -- Eliminar todas las versiones de register_delivery_agent
  FOR r IN 
    SELECT oid::regprocedure as func_signature
    FROM pg_proc 
    WHERE proname = 'register_delivery_agent' 
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.func_signature || ' CASCADE';
    RAISE NOTICE 'Eliminada función: %', r.func_signature;
  END LOOP;

  RAISE NOTICE '✅ Limpieza completada';
END $$;

-- ====================================
-- PASO 3: VERIFICAR LIMPIEZA
-- ====================================

SELECT 
  '✅ VERIFICACIÓN: Funciones después de limpieza' as etapa;

SELECT 
  COALESCE(COUNT(*), 0) as funciones_restantes
FROM pg_catalog.pg_proc p
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('register_client', 'register_restaurant', 'register_delivery_agent');

-- ====================================
-- RESULTADO ESPERADO
-- ====================================

SELECT 
  '📋 PRÓXIMOS PASOS' as etapa,
  'Si funciones_restantes = 0, ejecuta en orden:
   1. supabase_scripts/refactor_2025/06_create_register_client.sql
   2. supabase_scripts/refactor_2025/07_create_register_restaurant.sql
   3. supabase_scripts/refactor_2025/08_create_register_delivery_agent.sql
   4. supabase_scripts/refactor_2025/10_test_registrations_fixed_v3.sql' as instrucciones;
