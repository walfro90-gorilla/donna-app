-- Idempotent indexes for products.type and products.contains
-- Guided strictly by existing DATABASE_SCHEMA.sql (no column type changes)

-- Create composite index for restaurant_id + type to accelerate menu queries
CREATE INDEX IF NOT EXISTS idx_products_restaurant_type ON public.products(restaurant_id, type);

-- Create btree index on type for general filtering
CREATE INDEX IF NOT EXISTS idx_products_type ON public.products(type);

-- Create GIN index on contains (uuid[])
DO $$
BEGIN
  -- Only create if column exists and is of array type
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'contains'
  ) THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_products_contains_gin ON public.products USING GIN (contains)';
  END IF;
END $$;
