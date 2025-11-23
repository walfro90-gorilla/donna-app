-- ============================================================================
-- 2025-11-12_11_RPC_upsert_combo_atomic_v2.sql
-- 
-- Upserta un combo de forma atómica:
-- 1. Upserta el producto con type='combo'
-- 2. Upserta/crea el registro en product_combos
-- 3. Reemplaza completamente los items en product_combo_items
-- 4. El trigger de sincronización actualiza products.contains automáticamente
-- 5. Las validaciones diferidas se ejecutan al final de la transacción
-- 
-- Esta versión NO requiere que 'contains' sea enviado, se maneja automáticamente.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.upsert_combo_atomic(
  p_combo_product_id UUID,           -- NULL para crear nuevo, UUID para actualizar
  p_restaurant_id UUID,
  p_name TEXT,
  p_description TEXT,
  p_price NUMERIC,
  p_image_url TEXT,
  p_is_available BOOLEAN,
  p_items JSONB                      -- [{"product_id": "uuid", "quantity": int}, ...]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_product_id UUID;
  v_combo_id UUID;
  v_item JSONB;
  v_item_product_id UUID;
  v_item_qty INT;
  v_item_type TEXT;
  v_result JSONB;
BEGIN
  -- Validar que p_items no esté vacío
  IF p_items IS NULL OR jsonb_array_length(p_items) < 1 THEN
    RAISE EXCEPTION 'Un combo debe contener al menos 1 producto en p_items';
  END IF;

  -- PASO 1: Upsert del producto con type='combo'
  -- Si p_combo_product_id es NULL, crea un nuevo producto; de lo contrario, actualiza
  IF p_combo_product_id IS NULL THEN
    -- Crear nuevo producto
    INSERT INTO public.products (
      restaurant_id,
      name,
      description,
      price,
      image_url,
      is_available,
      type,
      contains,                     -- Inicializar como array vacío
      created_at,
      updated_at
    ) VALUES (
      p_restaurant_id,
      p_name,
      p_description,
      p_price,
      p_image_url,
      COALESCE(p_is_available, TRUE),
      'combo'::product_type_enum,
      '[]'::JSONB,                  -- Será llenado por el trigger de sincronización
      NOW(),
      NOW()
    )
    RETURNING id INTO v_product_id;
  ELSE
    -- Actualizar producto existente
    UPDATE public.products
    SET
      name = p_name,
      description = p_description,
      price = p_price,
      image_url = p_image_url,
      is_available = COALESCE(p_is_available, is_available),
      type = 'combo'::product_type_enum,
      updated_at = NOW()
    WHERE id = p_combo_product_id
      AND restaurant_id = p_restaurant_id
    RETURNING id INTO v_product_id;

    IF v_product_id IS NULL THEN
      RAISE EXCEPTION 'Producto % no encontrado o no pertenece al restaurante %', 
        p_combo_product_id, p_restaurant_id;
    END IF;
  END IF;

  -- PASO 2: Upsert en product_combos
  INSERT INTO public.product_combos (product_id, restaurant_id, created_at, updated_at)
  VALUES (v_product_id, p_restaurant_id, NOW(), NOW())
  ON CONFLICT (product_id) 
  DO UPDATE SET 
    updated_at = NOW()
  RETURNING id INTO v_combo_id;

  -- PASO 3: Reemplazar items del combo (DELETE + INSERT)
  DELETE FROM public.product_combo_items pci
  USING public.product_combos pc
  WHERE pci.combo_id = pc.id
    AND pc.product_id = v_product_id;

  -- PASO 4: Insertar nuevos items
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_item_product_id := (v_item->>'product_id')::UUID;
    v_item_qty := COALESCE((v_item->>'quantity')::INT, 1);

    -- Validar que el producto del item exista y no sea combo
    SELECT p.type::TEXT INTO v_item_type
    FROM public.products p
    WHERE p.id = v_item_product_id
      AND p.restaurant_id = p_restaurant_id;

    IF v_item_type IS NULL THEN
      RAISE EXCEPTION 'Producto % no encontrado en restaurante %', 
        v_item_product_id, p_restaurant_id;
    END IF;

    IF v_item_type = 'combo' THEN
      RAISE EXCEPTION 'No se puede agregar un combo (%) dentro de otro combo (recursión prohibida)', 
        v_item_product_id;
    END IF;

    IF v_item_qty < 1 THEN
      RAISE EXCEPTION 'La cantidad de producto % debe ser al menos 1', v_item_product_id;
    END IF;

    -- Insertar item
    INSERT INTO public.product_combo_items (combo_id, product_id, quantity, created_at)
    VALUES (v_combo_id, v_item_product_id, v_item_qty, NOW());
  END LOOP;

  -- PASO 5: El trigger fn_sync_combo_contains() actualizará products.contains automáticamente
  -- PASO 6: El trigger fn_validate_combo_deferred() validará al final de la transacción

  -- Retornar resultado
  SELECT jsonb_build_object(
    'success', TRUE,
    'product_id', v_product_id,
    'combo_id', v_combo_id,
    'message', 'Combo guardado exitosamente'
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- Permisos explícitos usando la firma para evitar ambigüedad
GRANT EXECUTE ON FUNCTION public.upsert_combo_atomic(
  UUID, UUID, TEXT, TEXT, NUMERIC, TEXT, BOOLEAN, JSONB
) TO anon, authenticated;

COMMENT ON FUNCTION public.upsert_combo_atomic(UUID, UUID, TEXT, TEXT, NUMERIC, TEXT, BOOLEAN, JSONB) IS 
'Upserta un combo de forma atómica. El campo contains se sincroniza automáticamente mediante trigger.';
