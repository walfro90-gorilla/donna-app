-- ============================================================================
-- 2025-11-12_10_DROP_old_trigger.sql
-- 
-- Elimina el trigger antiguo fn_validate_combo_items_and_bounds() que validaba
-- en cada INSERT individual, causando fallos en inserts batch.
-- ============================================================================

DROP TRIGGER IF EXISTS trg_validate_combo_items_and_bounds ON public.product_combo_items;
DROP FUNCTION IF EXISTS public.fn_validate_combo_items_and_bounds() CASCADE;

-- Log de confirmación
DO $$
BEGIN
  RAISE NOTICE 'Trigger antiguo fn_validate_combo_items_and_bounds eliminado exitosamente.';
END $$;
