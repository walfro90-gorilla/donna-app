-- Migración 1: Convertir products.type de TEXT a ENUM con valores expandidos
-- Valores: principal, bebida, postre, entrada, combo
-- Idempotente: solo ejecuta si type es TEXT o no existe

DO $$ 
DECLARE
  type_col_type text;
BEGIN
  -- 1) Verificar si la columna existe y su tipo
  SELECT data_type INTO type_col_type
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'products'
    AND column_name = 'type';

  -- 2) Crear ENUM si no existe
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'product_type') THEN
    CREATE TYPE product_type AS ENUM ('principal', 'bebida', 'postre', 'entrada', 'combo');
    RAISE NOTICE 'ENUM product_type creado';
  ELSE
    RAISE NOTICE 'ENUM product_type ya existe';
  END IF;

  -- 3) Si la columna no existe, crearla como ENUM
  IF type_col_type IS NULL THEN
    ALTER TABLE products
      ADD COLUMN type product_type NOT NULL DEFAULT 'principal';
    RAISE NOTICE 'Columna type añadida como product_type';
    
  -- 4) Si existe como TEXT, convertir a ENUM
  ELSIF type_col_type = 'text' THEN
    -- Primero cambiar valores existentes a los nuevos
    -- 'single' → 'principal'
    -- 'combo' → 'combo'
    UPDATE products SET type = 'principal' WHERE type = 'single';
    
    -- Ahora cambiar tipo de columna
    ALTER TABLE products 
      ALTER COLUMN type TYPE product_type 
      USING (type::product_type);
    
    RAISE NOTICE 'Columna type convertida de TEXT a product_type ENUM';
  ELSE
    RAISE NOTICE 'Columna type ya es product_type ENUM';
  END IF;

  -- 5) Backfill: productos con combos → 'combo', resto → 'principal'
  UPDATE products p
  SET type = 'combo'
  WHERE EXISTS (
    SELECT 1 FROM product_combos c WHERE c.product_id = p.id
  ) AND type = 'principal';

END $$;

-- 6) Índice para filtrar por restaurante y tipo
CREATE INDEX IF NOT EXISTS idx_products_restaurant_type
  ON products(restaurant_id, type);

COMMENT ON COLUMN products.type IS 'Tipo de producto: principal, bebida, postre, entrada, combo';
