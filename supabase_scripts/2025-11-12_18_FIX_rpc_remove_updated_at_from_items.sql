-- =============================================================================
-- 2025-11-12_18_FIX_rpc_remove_updated_at_from_items.sql
-- 
-- Propósito
--   Error actual: 42703 column "updated_at" of relation "product_combo_items" does not exist
--   Causa: La RPC upsert_combo_atomic insertaba en product_combo_items(col ..., created_at, updated_at)
--          pero según DATABASE_SCHEMA.sql, product_combo_items SOLO tiene:
--          id, combo_id, product_id, quantity, created_at
-- 
-- Fix quirúrgico
--   Reemplazar la función public.upsert_combo_atomic(jsonb, jsonb, uuid)
--   para que:
--     - Ya NO use la columna updated_at en product_combo_items
--     - Inserte únicamente (combo_id, product_id, quantity) dejando created_at por DEFAULT
--     - Mantenga el resto de validaciones y actualice updated_at únicamente en product_combos
--     - Calcule products.contains SIEMPRE desde items (ignora product.contains del cliente)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.upsert_combo_atomic(
  product jsonb,
  items jsonb,
  product_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_product_id uuid := product_id;
  v_combo_id uuid;
  v_restaurant_id uuid := (product->>'restaurant_id')::uuid;
  v_total_units int;
  v_has_nested_combos int;
  v_product_row jsonb;
  v_combo_row jsonb;
  v_computed_contains jsonb;
BEGIN
  -- 1) Validación: items debe ser un arreglo JSON válido y no vacío
  IF items IS NULL OR jsonb_typeof(items) <> 'array' OR jsonb_array_length(items) = 0 THEN
    RAISE EXCEPTION 'El combo debe tener al menos 1 item válido';
  END IF;

  -- 2) Calcular contains desde items (SIEMPRE, ignorando product.contains)
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'product_id', (elem->>'product_id')::TEXT,
        'quantity', GREATEST(1, COALESCE((elem->>'quantity')::int, 1))
      )
    ),
    '[]'::jsonb
  )
  INTO v_computed_contains
  FROM jsonb_array_elements(items) elem
  WHERE elem ? 'product_id' AND (elem->>'product_id') IS NOT NULL;

  IF v_computed_contains IS NULL OR jsonb_array_length(v_computed_contains) = 0 THEN
    RAISE EXCEPTION 'El combo debe tener al menos 1 item con product_id válido';
  END IF;

  -- 3) Validación: total de unidades 2..9
  SELECT COALESCE(SUM(GREATEST(1, COALESCE((elem->>'quantity')::int, 1))), 0)
    INTO v_total_units
  FROM jsonb_array_elements(v_computed_contains) elem;

  IF v_total_units < 2 OR v_total_units > 9 THEN
    RAISE EXCEPTION 'Un combo debe tener entre 2 y 9 unidades en total (actual=%)', v_total_units;
  END IF;

  -- 4) Validación: prohibir combos dentro de combos
  SELECT COUNT(*) INTO v_has_nested_combos
  FROM products p
  WHERE p.id IN (
    SELECT (e->>'product_id')::uuid 
    FROM jsonb_array_elements(v_computed_contains) e
  )
  AND p.type::text = 'combo';

  IF v_has_nested_combos > 0 THEN
    RAISE EXCEPTION 'No se permiten combos dentro de combos (recursión prohibida)';
  END IF;

  -- 5) Bypass de validaciones row-level durante carga batch
  PERFORM set_config('combo.bypass_validate', 'on', true);

  -- 6) UPSERT del producto (type='combo', contains calculado)
  IF v_product_id IS NULL THEN
    INSERT INTO products (
      restaurant_id,
      name,
      description,
      price,
      image_url,
      is_available,
      type,
      contains,
      created_at,
      updated_at
    ) VALUES (
      v_restaurant_id,
      NULLIF(product->>'name', ''),
      NULLIF(product->>'description', ''),
      (product->>'price')::numeric,
      NULLIF(product->>'image_url', ''),
      COALESCE((product->>'is_available')::boolean, true),
      'combo',
      v_computed_contains,
      COALESCE((product->>'created_at')::timestamptz, v_now),
      v_now
    ) RETURNING id INTO v_product_id;
  ELSE
    UPDATE products SET
      name = NULLIF(product->>'name', ''),
      description = NULLIF(product->>'description', ''),
      price = (product->>'price')::numeric,
      image_url = NULLIF(product->>'image_url', ''),
      is_available = COALESCE((product->>'is_available')::boolean, true),
      type = 'combo',
      contains = v_computed_contains,
      updated_at = v_now
    WHERE id = v_product_id
    RETURNING id INTO v_product_id;
  END IF;

  IF v_product_id IS NULL THEN
    RAISE EXCEPTION 'No se pudo crear/actualizar el producto del combo';
  END IF;

  -- 7) Asegurar fila en product_combos
  SELECT pc.id INTO v_combo_id 
  FROM public.product_combos pc 
  WHERE pc.product_id = v_product_id;

  IF v_combo_id IS NULL THEN
    INSERT INTO public.product_combos (product_id, restaurant_id, created_at, updated_at)
    VALUES (v_product_id, v_restaurant_id, v_now, v_now)
    RETURNING id INTO v_combo_id;
  ELSE
    UPDATE public.product_combos 
    SET updated_at = v_now 
    WHERE id = v_combo_id;
  END IF;

  -- 8) Reemplazar items del combo (DELETE + INSERT batch)
  DELETE FROM public.product_combo_items pci 
  WHERE pci.combo_id = v_combo_id;

  -- IMPORTANTE: product_combo_items NO tiene updated_at según DATABASE_SCHEMA.sql
  --             Insertar solo columnas reales y dejar created_at con DEFAULT
  INSERT INTO public.product_combo_items (combo_id, product_id, quantity)
  SELECT 
    v_combo_id,
    (e->>'product_id')::uuid,
    GREATEST(1, COALESCE((e->>'quantity')::int, 1)) AS quantity
  FROM jsonb_array_elements(v_computed_contains) e;

  -- 9) Desactivar bypass
  PERFORM set_config('combo.bypass_validate', 'off', true);

  -- 10) Respuesta
  SELECT to_jsonb(p.*) INTO v_product_row 
  FROM public.products p 
  WHERE p.id = v_product_id;

  SELECT to_jsonb(c.*) INTO v_combo_row 
  FROM public.product_combos c 
  WHERE c.id = v_combo_id;

  RETURN jsonb_build_object('product', v_product_row, 'combo', v_combo_row);

EXCEPTION WHEN OTHERS THEN
  -- Asegurar que bypass se limpia incluso en error
  PERFORM set_config('combo.bypass_validate', 'off', true);
  RAISE; -- Re-lanzar el error original
END;
$$;

-- Permisos
GRANT EXECUTE ON FUNCTION public.upsert_combo_atomic(jsonb, jsonb, uuid) 
TO anon, authenticated, service_role;

-- Comentario
COMMENT ON FUNCTION public.upsert_combo_atomic(jsonb, jsonb, uuid) IS 
'Upserta combos de forma atómica. Calcula contains desde items, valida 2-9, evita combos anidados. Inserta product_combo_items sin updated_at.';
