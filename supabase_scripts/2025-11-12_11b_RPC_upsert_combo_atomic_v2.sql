-- Nueva versión de la RPC para upsert de combos de manera atómica
-- Core: upsert_combo_atomic_v2(p_product_id uuid, p_items jsonb)
-- Wrapper público compatible: upsert_combo_atomic(p_product_id uuid, p_items jsonb)

-- Nota: Ajusta el tipo ENUM si tu proyecto usa un nombre distinto al de ejemplo 'product_type'.
-- Si tu enum es product_type_enum, cambia '::product_type' por '::product_type_enum' en las líneas marcadas.

CREATE OR REPLACE FUNCTION public.upsert_combo_atomic_v2(
  p_product_id uuid,
  p_items jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_combo_id uuid;
  v_total_units int;
  v_item jsonb;
  v_item_product_id uuid;
  v_item_qty int;
BEGIN
  -- Validación de entrada: p_items debe ser un arreglo JSON con al menos 2 unidades en total y máx 9
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'products.contains no puede ser NULL/vacío y debe ser un arreglo JSON cuando type = combo';
  END IF;

  SELECT COALESCE(SUM( (e.value->>'quantity')::int ), 0)
    INTO v_total_units
  FROM jsonb_array_elements(p_items) AS e
  WHERE (e.value ? 'quantity');

  IF v_total_units < 2 OR v_total_units > 9 THEN
    RAISE EXCEPTION 'Un combo debe tener entre 2 y 9 unidades en total (actual=%)', v_total_units;
  END IF;

  -- Forzamos type='combo' y seteamos contains como el cache denormalizado
  IF p_product_id IS NULL THEN
    INSERT INTO public.products (type, contains)
    VALUES ('combo'::product_type, p_items) -- <-- ajusta a ::product_type_enum si aplica
    RETURNING id INTO v_combo_id;
  ELSE
    UPDATE public.products
       SET type = 'combo'::product_type,     -- <-- ajusta a ::product_type_enum si aplica
           contains = p_items
     WHERE id = p_product_id
     RETURNING id INTO v_combo_id;
  END IF;

  -- Bypass validaciones por-trigger durante la carga de ítems (si tu validación lo soporta)
  PERFORM set_config('combo.bypass_validate', 'on', true);

  -- Sincronizamos los ítems del combo de forma atómica
  DELETE FROM public.product_combo_items WHERE combo_id = v_combo_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_item_product_id := NULLIF((v_item->>'product_id'), '')::uuid;
    v_item_qty        := NULLIF((v_item->>'quantity'), '')::int;

    IF v_item_product_id IS NULL OR v_item_qty IS NULL OR v_item_qty <= 0 THEN
      RAISE EXCEPTION 'Ítem inválido. Se requiere product_id (uuid) y quantity (>0). Item=%', v_item;
    END IF;

    INSERT INTO public.product_combo_items (combo_id, product_id, quantity)
    VALUES (v_combo_id, v_item_product_id, v_item_qty);
  END LOOP;

  RETURN v_combo_id;
END;
$$;

COMMENT ON FUNCTION public.upsert_combo_atomic_v2(uuid, jsonb)
  IS 'Upserta combos de forma atómica. type=combo, contains cache JSON y product_combo_items sincronizado.';

GRANT EXECUTE ON FUNCTION public.upsert_combo_atomic_v2(uuid, jsonb) TO anon, authenticated, service_role;

-- Wrapper compatible usando el mismo nombre público habitual
CREATE OR REPLACE FUNCTION public.upsert_combo_atomic(
  p_product_id uuid,
  p_items jsonb
)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.upsert_combo_atomic_v2(p_product_id, p_items);
$$;

COMMENT ON FUNCTION public.upsert_combo_atomic(uuid, jsonb)
  IS 'Wrapper hacia upsert_combo_atomic_v2. Usar este nombre en el cliente.';

GRANT EXECUTE ON FUNCTION public.upsert_combo_atomic(uuid, jsonb) TO anon, authenticated, service_role;
