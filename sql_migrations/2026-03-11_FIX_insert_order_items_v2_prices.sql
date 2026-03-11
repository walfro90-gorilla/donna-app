-- Fix: insert_order_items_v2 ahora lee 'price' y guarda en price_at_time_of_order Y unit_price.
-- Antes leía v_item->>'price' pero Flutter enviaba 'unit_price' → ambas columnas quedaban en 0.
-- Ahora Flutter envía 'price' (fix en supabase_config.dart) y el RPC guarda en ambas columnas.
--
-- IMPORTANTE: Eliminar AMBAS sobrecargas (json y jsonb) para evitar PGRST203 "Multiple Choices".
DROP FUNCTION IF EXISTS public.insert_order_items_v2(uuid, json);
DROP FUNCTION IF EXISTS public.insert_order_items_v2(uuid, jsonb);

CREATE OR REPLACE FUNCTION public.insert_order_items_v2(
  p_order_id uuid,
  p_items jsonb
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item jsonb;
  v_price double precision;
  v_count integer := 0;
BEGIN
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    -- Acepta 'price', 'unit_price' o 'price_at_time_of_order' como fuente del precio
    v_price := COALESCE(
      NULLIF((v_item->>'price')::double precision, 0),
      NULLIF((v_item->>'unit_price')::double precision, 0),
      (v_item->>'price_at_time_of_order')::double precision,
      0
    );

    INSERT INTO public.order_items (
      id, order_id, product_id, quantity,
      price_at_time_of_order, unit_price,
      created_at
    ) VALUES (
      gen_random_uuid(),
      p_order_id,
      (v_item->>'product_id')::uuid,
      (v_item->>'quantity')::integer,
      v_price,
      v_price,
      now()
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN json_build_object('success', true, 'items_inserted', v_count);

EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.insert_order_items_v2(uuid, jsonb) TO authenticated;
