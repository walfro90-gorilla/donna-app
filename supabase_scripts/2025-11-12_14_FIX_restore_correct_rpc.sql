-- ============================================================================
-- 2025-11-12_14_FIX_restore_correct_rpc.sql
-- 
-- Restaura la RPC upsert_combo_atomic con la firma CORRECTA que el cliente espera:
--   upsert_combo_atomic(product jsonb, items jsonb, product_id uuid default null)
-- 
-- Esta versión:
-- 1. Acepta product (Map completo) + items (List) + product_id (UUID opcional)
-- 2. Valida bounds 2-9 unidades
-- 3. Impide recursión de combos
-- 4. Rellena products.contains automáticamente con items
-- 5. Usa bypass_validate para permitir batch insert sin trigger BEFORE
-- ============================================================================

-- Limpieza: eliminar todas las versiones anteriores
DROP FUNCTION IF EXISTS public.upsert_combo_atomic(uuid, jsonb);
DROP FUNCTION IF EXISTS public.upsert_combo_atomic_v2(uuid, jsonb);

-- Crear la función con la firma correcta
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
BEGIN
  -- Validación 1: items debe ser un arreglo JSON válido y no vacío
  IF items IS NULL OR jsonb_typeof(items) <> 'array' OR jsonb_array_length(items) = 0 THEN
    RAISE EXCEPTION 'products.contains no puede ser NULL/vacío y debe ser un arreglo JSON cuando type = combo';
  END IF;

  -- Validación 2: Calcular total de unidades y validar rango (2..9)
  SELECT COALESCE(SUM(GREATEST(1, COALESCE((elem->>'quantity')::int, 1))), 0)
    INTO v_total_units
  FROM jsonb_array_elements(items) elem
  WHERE elem ? 'product_id' AND (elem->>'product_id') IS NOT NULL;

  IF v_total_units < 2 OR v_total_units > 9 THEN
    RAISE EXCEPTION 'Un combo debe tener entre 2 y 9 unidades en total (actual=%)', v_total_units;
  END IF;

  -- Validación 3: No permitir combos dentro de combos (recursión prohibida)
  SELECT COUNT(*) INTO v_has_nested_combos
  FROM products p
  WHERE p.id IN (
    SELECT (e->>'product_id')::uuid 
    FROM jsonb_array_elements(items) e
    WHERE e ? 'product_id'
  )
  AND p.type::text = 'combo';

  IF v_has_nested_combos > 0 THEN
    RAISE EXCEPTION 'No se permiten combos dentro de combos (recursión prohibida)';
  END IF;

  -- Activar bypass para evitar validación row-level durante batch insert
  PERFORM set_config('combo.bypass_validate', 'on', true);

  -- UPSERT del producto (siempre type='combo', contains=items)
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
      items::jsonb,
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
      contains = items::jsonb,
      updated_at = v_now
    WHERE id = v_product_id
    RETURNING id INTO v_product_id;
  END IF;

  IF v_product_id IS NULL THEN
    RAISE EXCEPTION 'No se pudo crear/actualizar el producto del combo';
  END IF;

  -- Asegurar que existe el registro en product_combos
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

  -- Reemplazar items del combo (DELETE + INSERT batch)
  DELETE FROM public.product_combo_items pci 
  WHERE pci.combo_id = v_combo_id;

  INSERT INTO public.product_combo_items (combo_id, product_id, quantity, created_at, updated_at)
  SELECT 
    v_combo_id,
    (e->>'product_id')::uuid,
    GREATEST(1, COALESCE((e->>'quantity')::int, 1)) AS quantity,
    v_now,
    v_now
  FROM jsonb_array_elements(items) e
  WHERE e ? 'product_id' AND (e->>'product_id') IS NOT NULL;

  -- Desactivar bypass
  PERFORM set_config('combo.bypass_validate', 'off', true);

  -- Retornar payload con producto y combo actualizados
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
  -- Re-lanzar el error original
  RAISE;
END;
$$;

-- Permisos
GRANT EXECUTE ON FUNCTION public.upsert_combo_atomic(jsonb, jsonb, uuid) 
TO anon, authenticated, service_role;

-- Comentario
COMMENT ON FUNCTION public.upsert_combo_atomic(jsonb, jsonb, uuid) IS 
'Upserta combos de forma atómica. Acepta product (Map), items (Array), y product_id opcional. Valida bounds 2-9, impide recursión, rellena contains automáticamente.';
