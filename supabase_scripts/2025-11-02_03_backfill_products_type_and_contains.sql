-- 2025-11-02_03_backfill_products_type_and_contains.sql
-- Purpose: Backfill products.type and products.contains based on existing combo relations
-- Notes:
--  - Avoids comparing ENUM against invalid literals ('' or 'single').
--  - Detects schema variants safely (product_combos.product_id vs combo_product_id, and
--    product_combo_items.product_id vs item_product_id) using information_schema.
--  - Idempotent: running multiple times is safe.

DO $$
DECLARE
  -- Column names detected at runtime to match your DATABASE_SCHEMA.sql
  combo_product_col text := NULL;   -- column in product_combos pointing to products.id (e.g., product_id or combo_product_id)
  item_product_col  text := NULL;   -- column in product_combo_items pointing to products.id (e.g., product_id or item_product_id)
  combo_id_col      text := NULL;   -- column in product_combo_items pointing to product_combos.id (usually combo_id)

  pc_has_product_id boolean;
  pc_has_combo_product_id boolean;
  pci_has_product_id boolean;
  pci_has_item_product_id boolean;
  pci_has_combo_id boolean;
BEGIN
  -- Detect product_combos -> products reference column
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'product_combos' AND column_name = 'product_id'
  ) INTO pc_has_product_id;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'product_combos' AND column_name = 'combo_product_id'
  ) INTO pc_has_combo_product_id;

  IF pc_has_product_id THEN
    combo_product_col := 'product_id';
  ELSIF pc_has_combo_product_id THEN
    combo_product_col := 'combo_product_id';
  ELSE
    RAISE NOTICE '[BACKFILL] product_combos lacks product_id/combo_product_id. Skipping type backfill to combo.';
  END IF;

  -- Detect product_combo_items -> products reference column
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'product_combo_items' AND column_name = 'product_id'
  ) INTO pci_has_product_id;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'product_combo_items' AND column_name = 'item_product_id'
  ) INTO pci_has_item_product_id;

  IF pci_has_item_product_id THEN
    item_product_col := 'item_product_id';
  ELSIF pci_has_product_id THEN
    item_product_col := 'product_id';
  ELSE
    RAISE NOTICE '[BACKFILL] product_combo_items lacks product_id/item_product_id. Skipping contains backfill.';
  END IF;

  -- Detect product_combo_items -> product_combos FK column (commonly combo_id)
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'product_combo_items' AND column_name = 'combo_id'
  ) INTO pci_has_combo_id;

  IF pci_has_combo_id THEN
    combo_id_col := 'combo_id';
  ELSE
    RAISE NOTICE '[BACKFILL] product_combo_items lacks combo_id. Skipping contains backfill.';
  END IF;

  -- 1) Mark products that are combos (type = 'combo') based on product_combos linkage
  IF combo_product_col IS NOT NULL THEN
    EXECUTE format($sql$
      UPDATE products p
      SET type = 'combo'
      WHERE p.type IS DISTINCT FROM 'combo'
        AND EXISTS (
          SELECT 1
          FROM product_combos pc
          WHERE pc.%I = p.id
        )
    $sql$, combo_product_col);
  END IF;

  -- 2) Set default type for remaining NULLs to 'principal' (do not overwrite any non-null)
  UPDATE products
  SET type = 'principal'
  WHERE type IS NULL;

  -- 3) Backfill contains (UUID[]) for combo products from product_combo_items
  IF combo_product_col IS NOT NULL AND item_product_col IS NOT NULL AND combo_id_col IS NOT NULL THEN
    EXECUTE format($sql$
      UPDATE products p
      SET contains = COALESCE(
        (
          SELECT ARRAY_AGG(i.%I ORDER BY i.%I)
          FROM product_combos pc
          JOIN product_combo_items i ON i.%I = pc.id
          WHERE pc.%I = p.id
        ), '{}'
      )::uuid[]
      WHERE p.type = 'combo'
    $sql$, item_product_col, item_product_col, combo_id_col, combo_product_col);
  END IF;

  RAISE NOTICE '[BACKFILL] products.type and products.contains backfill completed.';
END
$$ LANGUAGE plpgsql;
