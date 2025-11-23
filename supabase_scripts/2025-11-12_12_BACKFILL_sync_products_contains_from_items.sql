-- Backfill para sincronizar products.contains (cache) desde product_combo_items
-- Ejecuta este script para alinear combos existentes con el nuevo modelo

DO $$
DECLARE
  v_updated int := 0;
  v_skipped int := 0;
BEGIN
  -- Bypass de validaciones en triggers, si tu función de validación lo soporta
  PERFORM set_config('combo.bypass_validate', 'on', true);

  -- Actualiza solo combos válidos con total de unidades entre 2 y 9
  WITH items AS (
    SELECT i.combo_id AS product_id,
           jsonb_agg(jsonb_build_object('product_id', i.product_id, 'quantity', i.quantity)
                    ORDER BY i.product_id) AS items_json,
           SUM(i.quantity) AS total_units
    FROM public.product_combo_items i
    GROUP BY i.combo_id
  ), upd AS (
    UPDATE public.products p
       SET contains = it.items_json
      FROM items it
     WHERE p.id = it.product_id
       AND p.type::text = 'combo'
       AND it.total_units BETWEEN 2 AND 9
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_updated FROM upd;

  -- Contamos combos con unidades fuera de rango para informar
  WITH items AS (
    SELECT i.combo_id AS product_id,
           SUM(i.quantity) AS total_units
    FROM public.product_combo_items i
    GROUP BY i.combo_id
  )
  SELECT COUNT(*) INTO v_skipped
  FROM items it
  JOIN public.products p ON p.id = it.product_id
  WHERE p.type::text = 'combo'
    AND (it.total_units < 2 OR it.total_units > 9);

  RAISE NOTICE 'Combos sincronizados (contains actualizado): %', v_updated;
  RAISE NOTICE 'Combos saltados por unidades fuera de rango (2..9): %', v_skipped;
END $$;
