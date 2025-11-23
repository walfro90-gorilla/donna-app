-- =====================================================================
-- insert_order_items_v2
-- Versioned RPC to insert order items safely without dropping v1.
-- Compatible with app call: rpc('insert_order_items_v2', { p_order_id, p_items })
-- Returns JSON with { success, items_inserted, message | error, code }
-- Notes:
--  - Accepts JSON array of items. Keys supported: product_id/productId, quantity/qty,
--    price_at_time_of_order/unit_price/price
--  - Uses SECURITY DEFINER and search_path=public for RLS-safe execution
--  - Does NOT modify or drop existing insert_order_items()
-- =====================================================================

CREATE OR REPLACE FUNCTION public.insert_order_items_v2(
  p_order_id uuid,
  p_items json
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item json;
  v_product_id uuid;
  v_qty integer;
  v_price numeric;
  v_inserted integer := 0;
BEGIN
  -- Basic validations
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'p_order_id cannot be NULL';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.orders o WHERE o.id = p_order_id) THEN
    RAISE EXCEPTION 'Order with ID % does not exist', p_order_id;
  END IF;

  IF p_items IS NULL OR json_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'p_items must be a JSON array';
  END IF;

  -- Process each item
  FOR item IN SELECT * FROM json_array_elements(p_items)
  LOOP
    -- Extract and normalize fields
    v_product_id := COALESCE(
      NULLIF(item->>'product_id', '')::uuid,
      NULLIF(item->>'productId', '')::uuid
    );

    v_qty := COALESCE(
      NULLIF(item->>'quantity', '')::int,
      NULLIF(item->>'qty', '')::int,
      1
    );

    v_price := COALESCE(
      NULLIF(item->>'price_at_time_of_order', '')::numeric,
      NULLIF(item->>'unit_price', '')::numeric,
      NULLIF(item->>'price', '')::numeric,
      (SELECT p.price::numeric FROM public.products p WHERE p.id = v_product_id)
    );

    -- Validations
    IF v_product_id IS NULL THEN
      RAISE EXCEPTION 'product_id is required in each item: %', item;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.products p WHERE p.id = v_product_id) THEN
      RAISE EXCEPTION 'Product with ID % does not exist', v_product_id;
    END IF;

    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'quantity must be a positive integer in item: %', item;
    END IF;

    IF v_price IS NULL THEN
      RAISE EXCEPTION 'price could not be determined for item: %', item;
    END IF;

    -- Insert
    INSERT INTO public.order_items (
      id, order_id, product_id, quantity, price_at_time_of_order, created_at
    ) VALUES (
      gen_random_uuid(), p_order_id, v_product_id, v_qty, v_price, now()
    );

    v_inserted := v_inserted + 1;
  END LOOP;

  -- Success response
  RETURN json_build_object(
    'success', true,
    'items_inserted', v_inserted,
    'message', format('Inserted %s items for order %s', v_inserted, p_order_id)
  );

EXCEPTION
  WHEN OTHERS THEN
    -- Non-throwing JSON error response (app handles this format)
    RETURN json_build_object(
      'success', false,
      'error', SQLERRM,
      'code', SQLSTATE
    );
END;
$$;

-- Permissions
REVOKE ALL ON FUNCTION public.insert_order_items_v2(uuid, json) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.insert_order_items_v2(uuid, json) TO authenticated;
GRANT EXECUTE ON FUNCTION public.insert_order_items_v2(uuid, json) TO anon;

-- Optional: document the function
COMMENT ON FUNCTION public.insert_order_items_v2(uuid, json)
IS 'Versioned RPC to insert order items. Accepts JSON array with product_id/productId, quantity/qty, and price fields (price_at_time_of_order/unit_price/price). Returns JSON.';
