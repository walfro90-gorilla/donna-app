-- ============================================================================
-- 2025-11-12_09_VALIDATE_combo_deferred.sql
-- 
-- Valida restricciones de combos AL FINAL DE LA TRANSACCIÓN (constraint trigger)
-- para permitir inserts atómicos batch.
-- 
-- Validaciones:
-- 1. Combo debe tener entre 2 y 9 unidades totales (suma de quantities)
-- 2. Combo no puede contener otros combos (recursión prohibida)
-- 3. products.contains debe estar sincronizado con product_combo_items
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_validate_combo_deferred()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_product_id UUID;
  v_combo_type TEXT;
  v_total_units INT;
  v_contains_nested_combo BOOLEAN;
  v_contains_jsonb JSONB;
  v_expected_contains JSONB;
BEGIN
  -- Obtener product_id del combo
  IF TG_OP = 'DELETE' THEN
    SELECT pc.product_id INTO v_product_id
    FROM public.product_combos pc
    WHERE pc.id = OLD.combo_id;
  ELSE
    SELECT pc.product_id INTO v_product_id
    FROM public.product_combos pc
    WHERE pc.id = NEW.combo_id;
  END IF;

  IF v_product_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Verificar que el producto sea type='combo'
  SELECT p.type::TEXT, p.contains INTO v_combo_type, v_contains_jsonb
  FROM public.products p
  WHERE p.id = v_product_id;

  IF v_combo_type IS NULL OR v_combo_type <> 'combo' THEN
    RAISE EXCEPTION 'El producto % debe tener type=combo para tener items', v_product_id;
  END IF;

  -- Validación 1: Total de unidades entre 2 y 9
  SELECT COALESCE(SUM(pci.quantity), 0) INTO v_total_units
  FROM public.product_combo_items pci
  INNER JOIN public.product_combos pc ON pc.id = pci.combo_id
  WHERE pc.product_id = v_product_id;

  IF v_total_units < 2 THEN
    RAISE EXCEPTION 'Un combo debe tener al menos 2 unidades en total (actual=%)', v_total_units;
  END IF;

  IF v_total_units > 9 THEN
    RAISE EXCEPTION 'Un combo no puede tener más de 9 unidades en total (actual=%)', v_total_units;
  END IF;

  -- Validación 2: No puede contener otros combos (recursión prohibida)
  SELECT EXISTS(
    SELECT 1
    FROM public.product_combo_items pci
    INNER JOIN public.product_combos pc ON pc.id = pci.combo_id
    INNER JOIN public.products p_item ON p_item.id = pci.product_id
    WHERE pc.product_id = v_product_id
      AND p_item.type::TEXT = 'combo'
  ) INTO v_contains_nested_combo;

  IF v_contains_nested_combo THEN
    RAISE EXCEPTION 'Un combo no puede contener otros combos (recursión prohibida)';
  END IF;

  -- Validación 3: products.contains debe coincidir con product_combo_items
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
  INTO v_expected_contains
  FROM public.product_combo_items pci
  INNER JOIN public.product_combos pc ON pc.id = pci.combo_id
  WHERE pc.product_id = v_product_id;

  IF v_contains_jsonb IS NULL OR v_contains_jsonb <> v_expected_contains THEN
    RAISE WARNING 'products.contains desincronizado para combo %. Esperado: %, actual: %',
      v_product_id, v_expected_contains, v_contains_jsonb;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Trigger CONSTRAINT DEFERRED: se ejecuta al final de la transacción
DROP TRIGGER IF EXISTS trg_validate_combo_deferred ON public.product_combo_items;
CREATE CONSTRAINT TRIGGER trg_validate_combo_deferred
AFTER INSERT OR UPDATE OR DELETE
ON public.product_combo_items
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION public.fn_validate_combo_deferred();

COMMENT ON FUNCTION public.fn_validate_combo_deferred() IS 
'Valida restricciones de combos al final de la transacción: unidades 2-9, sin recursión, contains sincronizado.';
