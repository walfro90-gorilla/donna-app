-- Replace legacy array-based triggers with JSONB-aware triggers for products.contains
-- Safe to run multiple times

BEGIN;

-- 0) Drop legacy trigger/function if they exist (that used array_length on UUID[])
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname = 'products' AND t.tgname = 'trg_validate_product_contains'
  ) THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_validate_product_contains ON public.products';
  END IF;
EXCEPTION WHEN others THEN
  -- ignore
  NULL;
END $$;

DROP FUNCTION IF EXISTS public.validate_product_contains() CASCADE;

-- 1) Validation + normalization BEFORE trigger (JSONB version)
CREATE OR REPLACE FUNCTION public.fn_products_validate_type_contains()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  invalid_count integer;
BEGIN
  IF NEW.type::text = 'combo' THEN
    IF NEW.contains IS NULL OR jsonb_typeof(NEW.contains) <> 'array' OR jsonb_array_length(NEW.contains) = 0 THEN
      RAISE EXCEPTION 'products.contains no puede ser NULL/vacío y debe ser un arreglo JSON cuando type = combo';
    END IF;

    IF NEW.id IS NOT NULL THEN
      NEW.contains := COALESCE((
        SELECT jsonb_agg(elem)
        FROM jsonb_array_elements(NEW.contains) AS elem
        WHERE (NOT (elem ? 'product_id')) OR ((elem->>'product_id')::uuid IS DISTINCT FROM NEW.id)
      ), '[]'::jsonb);
    END IF;

    NEW.contains := COALESCE((
      WITH parsed AS (
        SELECT NULLIF(elem->>'product_id','') AS pid_text,
               COALESCE(NULLIF(elem->>'quantity','')::int, 1) AS qty
        FROM jsonb_array_elements(NEW.contains) AS elem
      ), valid AS (
        SELECT DISTINCT ON (pid_text) pid_text, qty
        FROM parsed
        WHERE pid_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        ORDER BY pid_text
      )
      SELECT jsonb_agg(jsonb_build_object('product_id', (pid_text)::uuid, 'quantity', GREATEST(qty,1))) FROM valid
    ), '[]'::jsonb);

    SELECT COUNT(*) INTO invalid_count
    FROM (
      SELECT (elem->>'product_id')::uuid AS pid
      FROM jsonb_array_elements(NEW.contains) AS elem
      WHERE elem ? 'product_id'
    ) c
    LEFT JOIN public.products p ON p.id = c.pid
    WHERE p.id IS NULL OR p.restaurant_id <> NEW.restaurant_id;

    IF invalid_count > 0 THEN
      RAISE EXCEPTION 'products.contains incluye productos inexistentes o de otro restaurante';
    END IF;
  ELSE
    NEW.contains := NULL;
  END IF;

  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_products_validate_type_contains ON public.products;
CREATE TRIGGER trg_products_validate_type_contains
BEFORE INSERT OR UPDATE OF type, contains ON public.products
FOR EACH ROW EXECUTE FUNCTION public.fn_products_validate_type_contains();


-- 2) AFTER trigger to synchronize product_combos and product_combo_items from contains (JSONB version)
CREATE OR REPLACE FUNCTION public.fn_products_sync_combo_meta()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  combo_rec record;
BEGIN
  IF to_regclass('public.product_combos') IS NULL OR to_regclass('public.product_combo_items') IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.type::text = 'combo' THEN
    SELECT * INTO combo_rec FROM public.product_combos WHERE product_id = NEW.id;
    IF NOT FOUND THEN
      INSERT INTO public.product_combos (product_id, restaurant_id, created_at)
      VALUES (NEW.id, NEW.restaurant_id, now());
      SELECT * INTO combo_rec FROM public.product_combos WHERE product_id = NEW.id;
    END IF;

    DELETE FROM public.product_combo_items WHERE combo_id = combo_rec.id;

    IF NEW.contains IS NOT NULL AND jsonb_typeof(NEW.contains) = 'array' AND jsonb_array_length(NEW.contains) > 0 THEN
      INSERT INTO public.product_combo_items (combo_id, product_id, quantity, created_at)
      SELECT combo_rec.id,
             (elem->>'product_id')::uuid,
             GREATEST(COALESCE(NULLIF(elem->>'quantity','')::int, 1), 1),
             now()
      FROM jsonb_array_elements(NEW.contains) AS elem
      WHERE elem ? 'product_id';
    END IF;
  ELSE
    DELETE FROM public.product_combos WHERE product_id = NEW.id;
  END IF;

  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_products_sync_combo_meta ON public.products;
CREATE TRIGGER trg_products_sync_combo_meta
AFTER INSERT OR UPDATE OF type, contains ON public.products
FOR EACH ROW EXECUTE FUNCTION public.fn_products_sync_combo_meta();

COMMIT;
