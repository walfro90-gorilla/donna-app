-- Safely add a 'type' column to products and backfill combos
-- Adheres to supabase_scripts/DATABASE_SCHEMA.sql structure

DO $$ BEGIN
  ALTER TABLE products
    ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'single'
      CHECK (type IN ('single','combo'));
EXCEPTION WHEN duplicate_column THEN
  -- ignore
  NULL;
END $$;

-- Backfill combos based on product_combos linkage
UPDATE products p
SET type = 'combo'
WHERE EXISTS (
  SELECT 1 FROM product_combos c WHERE c.product_id = p.id
);

-- Helpful index for filtering by restaurant and type
CREATE INDEX IF NOT EXISTS idx_products_restaurant_type
  ON products(restaurant_id, type);

COMMENT ON COLUMN products.type IS 'Tipo de producto: single | combo';
