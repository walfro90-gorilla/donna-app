-- Purpose: Re-crear upsert_combo_atomic con inserción de items robusta
-- Maneja esquemas donde product_combo_items tiene o no tiene updated_at.
-- Alineado a la app Flutter: firma (product jsonb, items jsonb, product_id uuid default null) returns jsonb

DO $$
BEGIN
  -- Eliminar versiones previas para evitar ambigüedad de sobrecargas
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'upsert_combo_atomic'
  ) THEN
    -- Borrar TODAS las firmas previas
    PERFORM
      format('DROP FUNCTION IF EXISTS public.upsert_combo_atomic(%s)', pg_get_function_identity_arguments(p.oid))
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'upsert_combo_atomic';
  END IF;
END$$;

CREATE OR REPLACE FUNCTION public.upsert_combo_atomic(
  product jsonb,
  items jsonb,
  product_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_product_id uuid;
  v_combo_id uuid;
  v_restaurant_id uuid;
  v_contains jsonb;
  v_now timestamptz := now();
  has_items_updated_at boolean := false;
BEGIN
  -- 1) Validar items y construir contains desde items
  IF COALESCE(jsonb_typeof(items), '') <> 'array' OR jsonb_array_length(items) = 0 THEN
    RAISE EXCEPTION 'P0001 items debe ser un arreglo no vacío';
  END IF;

  v_contains := (
    SELECT jsonb_agg(
             jsonb_build_object(
               'product_id', (elem->>'product_id')::uuid,
               'quantity', COALESCE((elem->>'quantity')::int, 1)
             )
           )
    FROM jsonb_array_elements(items) elem
  );

  IF v_contains IS NULL OR jsonb_array_length(v_contains) = 0 THEN
    RAISE EXCEPTION 'P0001 products.contains no puede ser NULL/vacío y debe ser un arreglo JSON cuando type = combo';
  END IF;

  -- 2) Determinar product_id y restaurant_id base
  v_product_id := COALESCE(product_id, (product->>'id')::uuid, gen_random_uuid());
  v_restaurant_id := COALESCE((product->>'restaurant_id')::uuid,
                              (SELECT restaurant_id FROM public.products WHERE id = v_product_id));

  -- 3) Upsert en products forzando type='combo' y contains desde items
  INSERT INTO public.products AS p
    (id, restaurant_id, name, description, price, image_url, is_available, type, contains, created_at, updated_at)
  VALUES
    (
      v_product_id,
      v_restaurant_id,
      COALESCE(product->>'name', (SELECT name FROM public.products WHERE id = v_product_id)),
      COALESCE(product->>'description', (SELECT description FROM public.products WHERE id = v_product_id)),
      COALESCE((product->>'price')::numeric, (SELECT price FROM public.products WHERE id = v_product_id)),
      COALESCE(product->>'image_url', (SELECT image_url FROM public.products WHERE id = v_product_id)),
      COALESCE((product->>'is_available')::boolean, (SELECT is_available FROM public.products WHERE id = v_product_id)),
      'combo',
      v_contains,
      v_now,
      v_now
    )
  ON CONFLICT (id) DO UPDATE SET
    restaurant_id = COALESCE(EXCLUDED.restaurant_id, p.restaurant_id),
    name          = COALESCE(EXCLUDED.name, p.name),
    description   = COALESCE(EXCLUDED.description, p.description),
    price         = COALESCE(EXCLUDED.price, p.price),
    image_url     = COALESCE(EXCLUDED.image_url, p.image_url),
    is_available  = COALESCE(EXCLUDED.is_available, p.is_available),
    type          = 'combo',
    contains      = v_contains,
    updated_at    = v_now
  RETURNING id INTO v_product_id;

  -- 4) Asegurar product_combos
  INSERT INTO public.product_combos AS pc (product_id, restaurant_id, created_at, updated_at)
  VALUES (v_product_id, v_restaurant_id, v_now, v_now)
  ON CONFLICT (product_id) DO UPDATE SET updated_at = v_now
  RETURNING id INTO v_combo_id;

  -- 5) Reemplazar items del combo
  DELETE FROM public.product_combo_items pci WHERE pci.combo_id = v_combo_id;

  -- Detectar si product_combo_items.updated_at existe para insertar condicionalmente
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'product_combo_items'
      AND column_name = 'updated_at'
  ) INTO has_items_updated_at;

  IF has_items_updated_at THEN
    INSERT INTO public.product_combo_items (combo_id, product_id, quantity, created_at, updated_at)
    SELECT v_combo_id,
           (elem->>'product_id')::uuid,
           COALESCE((elem->>'quantity')::int, 1),
           v_now,
           v_now
    FROM jsonb_array_elements(items) elem;
  ELSE
    INSERT INTO public.product_combo_items (combo_id, product_id, quantity, created_at)
    SELECT v_combo_id,
           (elem->>'product_id')::uuid,
           COALESCE((elem->>'quantity')::int, 1),
           v_now
    FROM jsonb_array_elements(items) elem;
  END IF;

  -- 6) Resultado
  RETURN jsonb_build_object(
    'product_id', v_product_id,
    'combo_id', v_combo_id,
    'contains', v_contains
  );
END
$$;

GRANT EXECUTE ON FUNCTION public.upsert_combo_atomic(jsonb, jsonb, uuid) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.upsert_combo_atomic(jsonb, jsonb, uuid) IS
'Upsert atómico de combos. Calcula contains desde items. Inserta product_combo_items con o sin updated_at según el esquema.';
