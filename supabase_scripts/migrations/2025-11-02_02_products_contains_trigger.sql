-- Migración 2: Añadir columna 'contains' y trigger de validación
-- contains: array de UUIDs de productos incluidos en el combo

-- 1) Añadir columna contains (array de UUID)
DO $$ BEGIN
  ALTER TABLE products
    ADD COLUMN IF NOT EXISTS contains UUID[] DEFAULT ARRAY[]::UUID[];
EXCEPTION WHEN duplicate_column THEN
  NULL;
END $$;

-- 2) Función trigger: valida que si type='combo' entonces contains tenga productos válidos
CREATE OR REPLACE FUNCTION validate_product_contains()
RETURNS TRIGGER AS $$
BEGIN
  -- Si NO es combo, contains debe estar vacío
  IF NEW.type <> 'combo' THEN
    IF NEW.contains IS NOT NULL AND array_length(NEW.contains, 1) > 0 THEN
      RAISE EXCEPTION 'Solo productos tipo combo pueden tener contains';
    END IF;
  ELSE
    -- Si es combo, contains debe tener al menos 1 producto válido
    IF NEW.contains IS NULL OR array_length(NEW.contains, 1) IS NULL THEN
      RAISE EXCEPTION 'Productos tipo combo deben tener al menos un producto en contains';
    END IF;
    
    -- Validar que todos los UUIDs en contains existen en products
    IF EXISTS (
      SELECT 1 FROM unnest(NEW.contains) AS item_id
      WHERE NOT EXISTS (SELECT 1 FROM products WHERE id = item_id AND restaurant_id = NEW.restaurant_id)
    ) THEN
      RAISE EXCEPTION 'Todos los productos en contains deben existir y pertenecer al mismo restaurante';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3) Crear trigger antes de INSERT o UPDATE
DROP TRIGGER IF EXISTS trg_validate_product_contains ON products;
CREATE TRIGGER trg_validate_product_contains
  BEFORE INSERT OR UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION validate_product_contains();

-- 4) Backfill: poblar contains desde product_combo_items para combos existentes
UPDATE products p
SET contains = (
  SELECT array_agg(pci.product_id)
  FROM product_combos pc
  JOIN product_combo_items pci ON pc.id = pci.combo_id
  WHERE pc.product_id = p.id
)
WHERE p.type = 'combo'
  AND EXISTS (
    SELECT 1 FROM product_combos pc WHERE pc.product_id = p.id
  );

COMMENT ON COLUMN products.contains IS 'Array de UUIDs de productos incluidos (solo para type=combo)';
