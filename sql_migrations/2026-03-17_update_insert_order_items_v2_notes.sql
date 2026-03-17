-- Update insert_order_items_v2 to accept and store per-item notes
CREATE OR REPLACE FUNCTION public.insert_order_items_v2(
  p_order_id uuid,
  p_items jsonb
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_item jsonb;
  v_count integer := 0;
BEGIN
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RETURN json_build_object('success', false, 'error', 'No items provided');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.order_items (
      id,
      order_id,
      product_id,
      quantity,
      price_at_time_of_order,
      notes,
      created_at
    ) VALUES (
      uuid_generate_v4(),
      p_order_id,
      (v_item->>'product_id')::uuid,
      (v_item->>'quantity')::integer,
      (v_item->>'price')::double precision,
      NULLIF(TRIM(v_item->>'notes'), ''),
      now()
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN json_build_object('success', true, 'inserted', v_count);
END;
$$;
