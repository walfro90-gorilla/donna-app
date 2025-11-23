-- ============================================================================
-- 2025-11-12_08_SYNC_contains_trigger.sql
-- 
-- Mantiene products.contains sincronizado automáticamente desde product_combo_items
-- como cache denormalizado. Se ejecuta DESPUÉS de INSERT/UPDATE/DELETE en items.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_sync_combo_contains()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_product_id UUID;
  v_new_contains JSONB;
BEGIN
  -- Determinar el product_id del combo afectado
  IF TG_OP = 'DELETE' THEN
    -- En DELETE, OLD contiene el registro eliminado
    SELECT pc.product_id INTO v_product_id
    FROM public.product_combos pc
    WHERE pc.id = OLD.combo_id;
  ELSE
    -- En INSERT/UPDATE, NEW contiene el registro actual
    SELECT pc.product_id INTO v_product_id
    FROM public.product_combos pc
    WHERE pc.id = NEW.combo_id;
  END IF;

  -- Si no encontramos product_id (combo ya eliminado), salir
  IF v_product_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Reconstruir contains desde product_combo_items
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'product_id', pci.product_id::TEXT,
        'quantity', pci.quantity
      )
      ORDER BY pci.created_at
    ),
    '[]'::JSONB
  )
  INTO v_new_contains
  FROM public.product_combo_items pci
  INNER JOIN public.product_combos pc ON pc.id = pci.combo_id
  WHERE pc.product_id = v_product_id;

  -- Actualizar products.contains
  UPDATE public.products
  SET 
    contains = v_new_contains,
    updated_at = NOW()
  WHERE id = v_product_id;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Trigger que se dispara DESPUÉS de cada modificación a product_combo_items
DROP TRIGGER IF EXISTS trg_sync_combo_contains_after ON public.product_combo_items;
CREATE TRIGGER trg_sync_combo_contains_after
AFTER INSERT OR UPDATE OR DELETE
ON public.product_combo_items
FOR EACH ROW
EXECUTE FUNCTION public.fn_sync_combo_contains();

COMMENT ON FUNCTION public.fn_sync_combo_contains() IS 
'Sincroniza automáticamente products.contains desde product_combo_items para mantener cache denormalizado.';
