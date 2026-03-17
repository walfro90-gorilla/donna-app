-- Actualizar insert_order_items_v2 para soportar modificadores seleccionados
-- Agregar RPCs upsert_modifier_group y upsert_modifier para gestión del restaurante

CREATE OR REPLACE FUNCTION public.insert_order_items_v2(p_order_id uuid, p_items jsonb)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_item      jsonb;
  v_modifier  jsonb;
  v_item_id   uuid;
  v_count     integer := 0;
BEGIN
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RETURN json_build_object('success', false, 'error', 'No items provided');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_item_id := uuid_generate_v4();

    INSERT INTO public.order_items (
      id, order_id, product_id, quantity, price_at_time_of_order, notes, created_at
    ) VALUES (
      v_item_id, p_order_id,
      (v_item->>'product_id')::uuid,
      (v_item->>'quantity')::integer,
      (v_item->>'price')::double precision,
      NULLIF(TRIM(v_item->>'notes'), ''),
      now()
    );

    IF v_item->'modifiers' IS NOT NULL AND jsonb_array_length(v_item->'modifiers') > 0 THEN
      FOR v_modifier IN SELECT * FROM jsonb_array_elements(v_item->'modifiers') LOOP
        INSERT INTO public.order_item_modifiers (
          id, order_item_id, modifier_id, modifier_group_id,
          name, group_name, price_delta, created_at
        ) VALUES (
          uuid_generate_v4(), v_item_id,
          NULLIF(v_modifier->>'modifier_id', '')::uuid,
          NULLIF(v_modifier->>'group_id', '')::uuid,
          v_modifier->>'name',
          v_modifier->>'group_name',
          COALESCE((v_modifier->>'price_delta')::double precision, 0.0),
          now()
        );
      END LOOP;
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN json_build_object('success', true, 'inserted', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_modifier_group(
  p_id uuid, p_product_id uuid, p_name text, p_description text,
  p_selection_type text, p_min_selections integer, p_max_selections integer,
  p_is_required boolean, p_sort_order integer
) RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_result uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.products p
    JOIN public.restaurants r ON p.restaurant_id = r.id
    WHERE p.id = p_product_id AND r.user_id = auth.uid()
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;
  INSERT INTO public.modifier_groups (
    id, product_id, name, description, selection_type,
    min_selections, max_selections, is_required, sort_order, updated_at
  ) VALUES (
    COALESCE(p_id, uuid_generate_v4()), p_product_id, p_name, p_description,
    p_selection_type, p_min_selections, p_max_selections, p_is_required, p_sort_order, now()
  )
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, description = EXCLUDED.description,
    selection_type = EXCLUDED.selection_type, min_selections = EXCLUDED.min_selections,
    max_selections = EXCLUDED.max_selections, is_required = EXCLUDED.is_required,
    sort_order = EXCLUDED.sort_order, updated_at = now()
  RETURNING id INTO v_result;
  RETURN json_build_object('success', true, 'id', v_result);
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_modifier(
  p_id uuid, p_group_id uuid, p_name text, p_description text,
  p_price_delta double precision, p_is_available boolean, p_sort_order integer
) RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_result uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.modifier_groups mg
    JOIN public.products p ON mg.product_id = p.id
    JOIN public.restaurants r ON p.restaurant_id = r.id
    WHERE mg.id = p_group_id AND r.user_id = auth.uid()
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;
  INSERT INTO public.modifiers (
    id, group_id, name, description, price_delta, is_available, sort_order, updated_at
  ) VALUES (
    COALESCE(p_id, uuid_generate_v4()), p_group_id, p_name, p_description,
    COALESCE(p_price_delta, 0.0), p_is_available, p_sort_order, now()
  )
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, description = EXCLUDED.description,
    price_delta = EXCLUDED.price_delta, is_available = EXCLUDED.is_available,
    sort_order = EXCLUDED.sort_order, updated_at = now()
  RETURNING id INTO v_result;
  RETURN json_build_object('success', true, 'id', v_result);
END;
$$;
