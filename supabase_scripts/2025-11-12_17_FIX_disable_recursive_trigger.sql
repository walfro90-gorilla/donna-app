-- ============================================================================
-- 2025-11-12_17_FIX_disable_recursive_trigger.sql
-- 
-- FIX DEFINITIVO: El error "stack depth limit exceeded" se debe a recursión 
-- infinita causada por el trigger trg_sync_combo_contains_after que actualiza
-- products.contains cada vez que se modifica product_combo_items, lo cual 
-- vuelve a disparar el trigger.
-- 
-- SOLUCIÓN: Deshabilitar el trigger de sincronización automática y dejar que
-- SOLO la RPC upsert_combo_atomic maneje products.contains.
-- ============================================================================

-- Paso 1: Deshabilitar el trigger de sincronización automática
DROP TRIGGER IF EXISTS trg_sync_combo_contains_after ON public.product_combo_items;

-- Paso 2: Marcar la función como obsoleta (mantenerla por si necesitamos restaurarla)
COMMENT ON FUNCTION public.fn_sync_combo_contains() IS 
'[DESHABILITADA] Sincronización automática desactivada para evitar recursión infinita. La RPC upsert_combo_atomic maneja contains directamente.';

-- Log de éxito
DO $$
BEGIN
  RAISE NOTICE '✅ Trigger trg_sync_combo_contains_after DESHABILITADO para prevenir recursión infinita.';
  RAISE NOTICE '✅ La RPC upsert_combo_atomic ahora maneja products.contains completamente.';
END $$;
