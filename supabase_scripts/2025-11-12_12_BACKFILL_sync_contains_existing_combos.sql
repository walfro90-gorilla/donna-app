-- ============================================================================
-- 2025-11-12_12_BACKFILL_sync_contains_existing_combos.sql
-- 
-- Sincroniza products.contains para todos los combos existentes en la base de datos
-- reconstruyendo el campo desde product_combo_items.
-- 
-- Este script es IDEMPOTENTE y puede ejecutarse múltiples veces sin causar daño.
-- ============================================================================

DO $$
DECLARE
  v_combo_record RECORD;
  v_new_contains JSONB;
  v_combos_updated INT := 0;
BEGIN
  RAISE NOTICE '=== INICIO: Sincronización de products.contains para combos existentes ===';

  -- Iterar sobre todos los productos de type='combo'
  FOR v_combo_record IN 
    SELECT 
      p.id AS product_id,
      p.name,
      p.contains AS current_contains
    FROM public.products p
    WHERE p.type = 'combo'::product_type_enum
    ORDER BY p.created_at
  LOOP
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
    WHERE pc.product_id = v_combo_record.product_id;

    -- Actualizar products.contains si ha cambiado
    IF v_combo_record.current_contains IS DISTINCT FROM v_new_contains THEN
      UPDATE public.products
      SET 
        contains = v_new_contains,
        updated_at = NOW()
      WHERE id = v_combo_record.product_id;

      v_combos_updated := v_combos_updated + 1;

      RAISE NOTICE '✓ Combo "%" (%) sincronizado. Antes: %, Ahora: %',
        v_combo_record.name,
        v_combo_record.product_id,
        v_combo_record.current_contains,
        v_new_contains;
    END IF;
  END LOOP;

  RAISE NOTICE '=== FIN: % combos sincronizados exitosamente ===', v_combos_updated;
END $$;
