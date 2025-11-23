-- =====================================================
-- FASE 2B: LIMPIEZA DE TRIGGERS CONFLICTIVOS
-- =====================================================
-- Elimina triggers que causan problemas de registro
-- Tiempo estimado: 2 minutos
-- =====================================================

BEGIN;

-- ====================================
-- TRIGGERS EN auth.users
-- ====================================
-- Este trigger es la principal fuente de conflictos
DROP TRIGGER IF EXISTS ensure_user_profile ON auth.users CASCADE;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users CASCADE;

-- ====================================
-- FUNCIONES DE TRIGGERS OBSOLETAS
-- ====================================
DROP FUNCTION IF EXISTS public.ensure_user_profile_public() CASCADE;
DROP FUNCTION IF EXISTS public.on_auth_user_created() CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;

-- ====================================
-- TRIGGERS EN public.users (si existen)
-- ====================================
DROP TRIGGER IF EXISTS update_users_updated_at ON public.users CASCADE;
DROP TRIGGER IF EXISTS validate_user_role ON public.users CASCADE;

-- ====================================
-- TRIGGERS EN productos (legacy)
-- ====================================
DROP TRIGGER IF EXISTS set_product_type_on_combo_insert ON public.product_combos CASCADE;
DROP TRIGGER IF EXISTS set_product_type_on_combo_delete ON public.product_combos CASCADE;
DROP TRIGGER IF EXISTS update_product_type_on_insert ON public.product_combo_items CASCADE;
DROP TRIGGER IF EXISTS update_product_type_on_delete ON public.product_combo_items CASCADE;

-- ====================================
-- TRIGGERS EN órdenes (conflictivos con payment processing)
-- ====================================
DROP TRIGGER IF EXISTS process_order_payment_trigger ON public.orders CASCADE;
DROP TRIGGER IF EXISTS order_status_update_trigger ON public.orders CASCADE;

-- Log de limpieza
INSERT INTO public.debug_logs (scope, message, meta)
VALUES (
  'REFACTOR_2025_CLEANUP',
  'Triggers conflictivos eliminados',
  jsonb_build_object(
    'timestamp', NOW(),
    'fase', '2B',
    'triggers_eliminados', 10
  )
);

COMMIT;

-- Verificación: Listar triggers que quedaron
SELECT 
  event_object_schema,
  event_object_table,
  trigger_name,
  event_manipulation,
  action_timing
FROM information_schema.triggers
WHERE event_object_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- ✅ Deberías ver solo triggers necesarios (updated_at, etc.)
