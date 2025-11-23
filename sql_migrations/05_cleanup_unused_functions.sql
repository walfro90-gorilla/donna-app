-- ============================================================================
-- LIMPIAR FUNCIONES NO UTILIZADAS O LEGACY
-- ============================================================================
-- Este archivo elimina funciones RPC antiguas que ya no se usan
-- y que pueden estar causando conflictos
-- ============================================================================

-- ============================================================================
-- PASO 1: Listar todas las funciones RPC actuales (DIAGNÓSTICO)
-- ============================================================================
DO $$
DECLARE
  rec RECORD;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔍 LISTANDO FUNCIONES RPC DISPONIBLES';
  RAISE NOTICE '========================================';
  
  FOR rec IN
    SELECT 
      n.nspname AS schema_name,
      p.proname AS function_name,
      pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname NOT LIKE 'pg_%'
      AND p.proname NOT LIKE 'uuid_%'
    ORDER BY p.proname
  LOOP
    RAISE NOTICE '  📌 %(%)', rec.function_name, rec.args;
  END LOOP;
  
  RAISE NOTICE '';
  RAISE NOTICE '✅ Listado de funciones completado';
  RAISE NOTICE '========================================';
END $$;

-- ============================================================================
-- PASO 2: Eliminar funciones legacy de registro
-- ============================================================================

-- create_user_profile_public (LEGACY - usar ensure_user_profile_v2)
DROP FUNCTION IF EXISTS public.create_user_profile_public(uuid, text, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.create_user_profile_public(uuid, text, text, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.create_user_profile_public(uuid, text, text, text, text, text) CASCADE;

RAISE NOTICE '✅ create_user_profile_public eliminado';

-- create_restaurant_public (LEGACY - usar register_restaurant_v2)
DROP FUNCTION IF EXISTS public.create_restaurant_public(uuid, text, text, text, text, text, boolean, text, double precision, double precision, text, jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.create_restaurant_public(uuid, text, text, text, boolean, text) CASCADE;
DROP FUNCTION IF EXISTS public.create_restaurant_public(uuid, text) CASCADE;

RAISE NOTICE '✅ create_restaurant_public eliminado';

-- create_account_public (LEGACY - usar ensure_account_v2)
DROP FUNCTION IF EXISTS public.create_account_public(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.create_account_public(uuid, text, double precision) CASCADE;

RAISE NOTICE '✅ create_account_public eliminado';

-- ============================================================================
-- PASO 3: Eliminar funciones de trigger problemáticas
-- ============================================================================

-- Status sync functions (causan el error OLD.status)
DROP FUNCTION IF EXISTS public.sync_delivery_agent_status() CASCADE;
DROP FUNCTION IF EXISTS public.update_delivery_agent_status() CASCADE;
DROP FUNCTION IF EXISTS public.sync_user_status() CASCADE;
DROP FUNCTION IF EXISTS public.handle_user_status_change() CASCADE;
DROP FUNCTION IF EXISTS public.validate_status_change() CASCADE;
DROP FUNCTION IF EXISTS public.check_status_field() CASCADE;

RAISE NOTICE '✅ Funciones de status sync eliminadas';

-- ============================================================================
-- PASO 4: Eliminar funciones de pago legacy
-- ============================================================================

-- Old payment processing functions
DROP FUNCTION IF EXISTS public.process_order_payment(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment_v1(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.handle_order_payment(uuid) CASCADE;

RAISE NOTICE '✅ Funciones de pago legacy eliminadas';

-- ============================================================================
-- PASO 5: Eliminar funciones duplicadas de ubicación
-- ============================================================================

-- Old location functions (if any duplicates exist)
DROP FUNCTION IF EXISTS public.update_location(uuid, double precision, double precision) CASCADE;
DROP FUNCTION IF EXISTS public.set_user_location(uuid, double precision, double precision) CASCADE;

RAISE NOTICE '✅ Funciones de ubicación duplicadas eliminadas';

-- ============================================================================
-- PASO 6: Verificación final - listar funciones restantes
-- ============================================================================
DO $$
DECLARE
  rec RECORD;
  v_count integer := 0;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ FUNCIONES RPC RESTANTES (ACTIVAS)';
  RAISE NOTICE '========================================';
  
  FOR rec IN
    SELECT 
      p.proname AS function_name,
      pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname NOT LIKE 'pg_%'
      AND p.proname NOT LIKE 'uuid_%'
      AND p.proname != 'app_log'
      AND p.proname != 'update_updated_at_column'
    ORDER BY p.proname
  LOOP
    v_count := v_count + 1;
    RAISE NOTICE '  ✅ %(%)', rec.function_name, rec.args;
  END LOOP;
  
  RAISE NOTICE '';
  RAISE NOTICE '📊 Total de funciones RPC activas: %', v_count;
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ ✅ ✅ LIMPIEZA COMPLETADA ✅ ✅ ✅';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE '🎯 FUNCIONES PRINCIPALES DISPONIBLES:';
  RAISE NOTICE '   ✅ ensure_user_profile_v2()';
  RAISE NOTICE '   ✅ ensure_account_v2()';
  RAISE NOTICE '   ✅ register_restaurant_v2()';
  RAISE NOTICE '   ✅ register_delivery_agent_atomic()';
  RAISE NOTICE '   ✅ update_user_location()';
  RAISE NOTICE '   ✅ update_client_default_address()';
  RAISE NOTICE '   ✅ create_order_safe()';
  RAISE NOTICE '   ✅ insert_order_items_v2()';
  RAISE NOTICE '   ✅ accept_order()';
  RAISE NOTICE '   ✅ upsert_combo_atomic()';
  RAISE NOTICE '';
  RAISE NOTICE '🚀 Sistema listo para operar';
  RAISE NOTICE '';
END $$;
