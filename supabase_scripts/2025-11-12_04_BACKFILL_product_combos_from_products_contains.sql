-- Purpose: Backfill product_combos and product_combo_items from products.contains
-- Notes:
--  - Qualifies all column references to avoid ambiguity (e.g., pci.combo_id)
--  - Uses variables with v_ prefix to avoid name collisions with column names
 --  - Expects: products.type::text = 'combo' and products.contains as jsonb
--  - Assumes product_combos has a unique row per products.id (product_id)
--  - Deletes existing items and re-inserts based on contains

BEGIN;

-- Activar bypass de validación solo durante esta transacción
SET LOCAL combo.bypass_validate = 'on';

DO $$
DECLARE
  rec RECORD;
  v_combo_id uuid;
  v_contains jsonb;
  v_total_units integer;
  v_item jsonb;
  v_item_product_id uuid;
  v_item_qty integer;
  v_restaurant_id uuid;
BEGIN
  -- No deshabilitamos triggers del sistema; el bypass de validación maneja los límites
  -- Iterate over all combo products
  FOR rec IN
    SELECT p.id AS product_id, p.restaurant_id AS restaurant_id
    FROM public.products p
    WHERE p.type::text = 'combo'
  LOOP
    -- Ensure a product_combos row exists and get its id
    SELECT pc.id INTO v_combo_id
    FROM public.product_combos pc
    WHERE pc.product_id = rec.product_id
    LIMIT 1;

    IF v_combo_id IS NULL THEN
      INSERT INTO public.product_combos (product_id, restaurant_id)
      VALUES (rec.product_id, rec.restaurant_id)
      RETURNING id INTO v_combo_id;
    END IF;

    -- Read the contains jsonb from the product
    SELECT p.contains INTO v_contains
    FROM public.products p
    WHERE p.id = rec.product_id
    LIMIT 1;

    -- If contains is null or not an array: purge items and mark unavailable
    IF v_contains IS NULL OR jsonb_typeof(v_contains) <> 'array' THEN
      DELETE FROM public.product_combo_items pci WHERE pci.combo_id = v_combo_id;
      UPDATE public.products p SET is_available = false, updated_at = now()
      WHERE p.id = rec.product_id AND p.is_available IS DISTINCT FROM false;
      CONTINUE;
    END IF;

    -- Compute total units across elements (sum of quantities clamped to 1..9)
    SELECT COALESCE(SUM(LEAST(GREATEST(COALESCE(NULLIF(elem->>'quantity','')::int, 1), 1), 9)), 0)
      INTO v_total_units
    FROM jsonb_array_elements(v_contains) AS elem;

    -- Enforce bounds 2..9 at batch level; if invalid, mark unavailable and skip
    IF v_total_units < 2 OR v_total_units > 9 THEN
      DELETE FROM public.product_combo_items pci WHERE pci.combo_id = v_combo_id;
      UPDATE public.products p SET is_available = false, updated_at = now()
      WHERE p.id = rec.product_id AND p.is_available IS DISTINCT FROM false;
      CONTINUE;
    END IF;

    -- Clean slate
    DELETE FROM public.product_combo_items pci WHERE pci.combo_id = v_combo_id;

    -- Insert valid items from contains, skipping nested combos
    INSERT INTO public.product_combo_items (combo_id, product_id, quantity)
    SELECT v_combo_id,
           (elem->>'product_id')::uuid AS product_id,
           LEAST(GREATEST(COALESCE(NULLIF(elem->>'quantity','')::int, 1), 1), 9) AS quantity
    FROM jsonb_array_elements(v_contains) AS elem
    JOIN public.products p2 ON p2.id = (elem->>'product_id')::uuid
    WHERE (elem ? 'product_id')
      AND p2.type::text <> 'combo';
  END LOOP;

  -- Limpieza del flag de bypass (scope local a la transacción)
END $$;

COMMIT;
