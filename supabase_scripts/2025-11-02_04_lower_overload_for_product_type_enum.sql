-- Purpose: Fix errors when policies/functions call lower() over the ENUM column products.type
-- Context: Postgres doesn't have lower(product_type_enum). Calling lower(enum) raises 42883.
-- Solution: Provide an overload lower(product_type_enum) -> text that delegates to lower(text).
-- This is safe, immutable, and doesn't change behavior of lower(text).

-- Note: Update the type name below if your enum differs. The error message shows product_type_enum.
-- If your enum is named differently (e.g., product_type), create another overload accordingly.

DO $$
BEGIN
  -- Create function only if not exists for the exact signature (product_type_enum)
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_type t ON t.oid = ANY(p.proargtypes)
    WHERE p.proname = 'lower'
      AND n.nspname = 'public'
      AND p.pronargs = 1
      AND t.typname = 'product_type_enum'
  ) THEN
    CREATE FUNCTION public.lower(product_type_enum)
    RETURNS text
    LANGUAGE sql
    IMMUTABLE
    STRICT
    AS $$
      SELECT lower(($1)::text);
    $$;
    COMMENT ON FUNCTION public.lower(product_type_enum) IS 'Overload to allow lower(enum) in policies/triggers; casts enum to text then lowers.';
  END IF;
END $$;

-- Optional: If your enum is named product_type (without _enum), also provide that overload
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'product_type') THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      JOIN pg_type t ON t.oid = ANY(p.proargtypes)
      WHERE p.proname = 'lower'
        AND n.nspname = 'public'
        AND p.pronargs = 1
        AND t.typname = 'product_type'
    ) THEN
      CREATE FUNCTION public.lower(product_type)
      RETURNS text
      LANGUAGE sql
      IMMUTABLE
      STRICT
      AS $$
        SELECT lower(($1)::text);
      $$;
      COMMENT ON FUNCTION public.lower(product_type) IS 'Overload to allow lower(enum) in policies/triggers; casts enum to text then lowers.';
    END IF;
  END IF;
END $$;
