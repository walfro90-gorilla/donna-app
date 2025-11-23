-- Migración 1: Crear ENUM product_type y columna type en products
-- Valores: principal, bebida, postre, entrada, combo

-- 1) Crear enum si no existe
DO $$ BEGIN
  CREATE TYPE product_type AS ENUM ('principal', 'bebida', 'postre', 'entrada', 'combo');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

-- 2) Añadir columna type con default 'principal'
DO $$ BEGIN
  ALTER TABLE products
    ADD COLUMN IF NOT EXISTS type product_type NOT NULL DEFAULT 'principal';
EXCEPTION WHEN duplicate_column THEN
  NULL;
END $$;

-- 3) Backfill: productos que ya tienen combos → 'combo', resto → 'principal'
UPDATE products p
SET type = 'combo'
WHERE EXISTS (
  SELECT 1 FROM product_combos c WHERE c.product_id = p.id
) AND type = 'principal';

-- 4) Índice para filtrar por restaurante y tipo
CREATE INDEX IF NOT EXISTS idx_products_restaurant_type
  ON products(restaurant_id, type);

COMMENT ON COLUMN products.type IS 'Tipo de producto: principal, bebida, postre, entrada, combo';
