-- ============================================================================
-- 2025-11-12_13_FIX_disable_old_before_trigger.sql
-- 
-- Deshabilita el trigger BEFORE obsoleto fn_validate_combo_items_and_bounds
-- que validaba síncronamente en cada INSERT y abortaba los batch inserts.
-- 
-- Ahora usamos el trigger CONSTRAINT DEFERRED fn_validate_combo_deferred
-- que valida al final de la transacción, permitiendo inserts batch atómicos.
-- ============================================================================

-- Eliminar triggers BEFORE obsoletos que validaban uno por uno
DROP TRIGGER IF EXISTS trg_validate_combo_items_and_bounds_i ON public.product_combo_items;
DROP TRIGGER IF EXISTS trg_validate_combo_items_and_bounds_u ON public.product_combo_items;
DROP TRIGGER IF EXISTS trg_validate_combo_items_and_bounds_d ON public.product_combo_items;

-- Comentar para referencia futura
COMMENT ON FUNCTION public.fn_validate_combo_items_and_bounds() IS 
'[OBSOLETO] Validación síncrona. Reemplazada por fn_validate_combo_deferred (CONSTRAINT TRIGGER DEFERRED).';
