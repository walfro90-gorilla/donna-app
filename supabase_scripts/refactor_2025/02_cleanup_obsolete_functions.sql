-- =====================================================
-- FASE 2A: LIMPIEZA DE FUNCIONES OBSOLETAS
-- =====================================================
-- Elimina RPCs legacy, duplicados y de testing
-- Tiempo estimado: 5 minutos
-- =====================================================

BEGIN;

-- ====================================
-- GRUPO 1: Funciones de registro legacy
-- ====================================
DROP FUNCTION IF EXISTS public.register_user(text, text, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.register_client(text, text, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.register_restaurant_v1(jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.register_restaurant_v2(jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.register_delivery_agent_v1(jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.register_delivery_agent_v2(jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.register_delivery_agent_atomic(jsonb) CASCADE;

-- ====================================
-- GRUPO 2: Funciones de validación legacy
-- ====================================
DROP FUNCTION IF EXISTS public.validate_email_unique(text) CASCADE;
DROP FUNCTION IF EXISTS public.validate_phone_unique(text) CASCADE;
DROP FUNCTION IF EXISTS public.validate_restaurant_name_unique(text) CASCADE;
DROP FUNCTION IF EXISTS public.check_email_exists(text) CASCADE;
DROP FUNCTION IF EXISTS public.check_phone_exists(text) CASCADE;

-- ====================================
-- GRUPO 3: Funciones de testing y debug
-- ====================================
DROP FUNCTION IF EXISTS public.test_create_order() CASCADE;
DROP FUNCTION IF EXISTS public.test_insert_order_items() CASCADE;
DROP FUNCTION IF EXISTS public.test_function_fixed() CASCADE;
DROP FUNCTION IF EXISTS public.debug_insert_function() CASCADE;
DROP FUNCTION IF EXISTS public.verification_simple() CASCADE;

-- ====================================
-- GRUPO 4: Funciones de proceso de órdenes legacy
-- ====================================
DROP FUNCTION IF EXISTS public.process_order_payment_v1(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment_v2(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment_v2_idempotent(uuid, text) CASCADE;

-- ====================================
-- GRUPO 5: Funciones de comisiones legacy
-- ====================================
DROP FUNCTION IF EXISTS public.fix_commission_bps() CASCADE;
DROP FUNCTION IF EXISTS public.fix_commission_bps_dynamic() CASCADE;
DROP FUNCTION IF EXISTS public.fix_commission_bps_and_trigger() CASCADE;

-- ====================================
-- GRUPO 6: Funciones de actualización de ubicación legacy
-- ====================================
DROP FUNCTION IF EXISTS public.update_user_location_v1(double precision, double precision) CASCADE;
DROP FUNCTION IF EXISTS public.update_user_location_v2(double precision, double precision, jsonb) CASCADE;

-- ====================================
-- GRUPO 7: Funciones de reviews legacy
-- ====================================
DROP FUNCTION IF EXISTS public.submit_review_v1(uuid, integer, text, text, uuid, uuid) CASCADE;
DROP FUNCTION IF EXISTS public.submit_review_canonical(uuid, integer, text, text, uuid, uuid) CASCADE;

-- ====================================
-- GRUPO 8: Funciones de balance y settlements legacy
-- ====================================
DROP FUNCTION IF EXISTS public.recompute_account_balance(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.fix_duplicate_transactions() CASCADE;

-- ====================================
-- GRUPO 9: Funciones de productos legacy
-- ====================================
DROP FUNCTION IF EXISTS public.backfill_products_type() CASCADE;
DROP FUNCTION IF EXISTS public.update_product_type_on_combo_change() CASCADE;

-- ====================================
-- GRUPO 10: Funciones de analytics y admin legacy
-- ====================================
DROP FUNCTION IF EXISTS public.get_admin_analytics_simple() CASCADE;

-- Log de limpieza
INSERT INTO public.debug_logs (scope, message, meta)
VALUES (
  'REFACTOR_2025_CLEANUP',
  'Funciones obsoletas eliminadas',
  jsonb_build_object(
    'timestamp', NOW(),
    'fase', '2A',
    'funciones_eliminadas', 30
  )
);

COMMIT;

-- Verificación: Listar funciones que quedaron
SELECT 
  routine_schema,
  routine_name,
  routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_type = 'FUNCTION'
ORDER BY routine_name;

-- ✅ Revisa que no haya funciones con nombres duplicados o legacy
