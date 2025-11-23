-- Purpose: Atomically create/update a combo product and its items in a single transaction
-- Ensures: 
--  - product.type = 'combo'
--  - items total units between 2 and 9
--  - items cannot reference other combos
--  - replaces product_combo_items in one shot
--  - bypasses row-level incremental validation using a scoped GUC
--
-- Call signature from app:
--   rpc('upsert_combo_atomic', {
--     product: {restaurant_id, name, description, price, image_url, is_available, ...},
--     items:   [{product_id: uuid, quantity: int}, ...],
--     product_id?: uuid
--   })

create or replace function public.upsert_combo_atomic(
  product jsonb,
  items jsonb,
  product_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  -- Always use a local variable so we never reference the argument name
  -- inside SQL statements, avoiding any ambiguity with columns.
  v_product_id uuid := product_id;
  v_combo_id uuid;
  v_restaurant_id uuid := (product->>'restaurant_id')::uuid;
  v_total_units int;
  v_has_nested_combos int;
  v_product_row jsonb;
  v_combo_row jsonb;
begin
  -- Validate inputs
  if items is null or jsonb_typeof(items) <> 'array' then
    raise exception 'items debe ser un arreglo JSON válido';
  end if;

  -- Compute total quantity and validate bounds (2..9)
  select coalesce(sum(greatest(1, coalesce((elem->>'quantity')::int, 1))), 0)
    into v_total_units
  from jsonb_array_elements(items) elem;

  if v_total_units < 2 or v_total_units > 9 then
    raise exception 'Un combo debe tener entre 2 y 9 unidades en total (actual=%).', v_total_units;
  end if;

  -- No combos inside combos
  select count(*) into v_has_nested_combos
  from products p
  where p.id in (
    select (e->>'product_id')::uuid from jsonb_array_elements(items) e
  )
  and p.type::text = 'combo';

  if v_has_nested_combos > 0 then
    raise exception 'No se permiten combos dentro de combos.';
  end if;

  -- Bypass row-level incremental validation while we replace the full set
  perform set_config('combo.bypass_validate', 'on', true);

  -- Upsert product
  if v_product_id is null then
    insert into products (
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
    ) values (
      v_restaurant_id,
      nullif(product->>'name',''),
      nullif(product->>'description',''),
      (product->>'price')::numeric,
      nullif(product->>'image_url',''),
      coalesce((product->>'is_available')::boolean, true),
      'combo',
      items::jsonb,
      coalesce((product->>'created_at')::timestamptz, v_now),
      v_now
    ) returning id into v_product_id;
  else
    update products set
      name = nullif(product->>'name',''),
      description = nullif(product->>'description',''),
      price = (product->>'price')::numeric,
      image_url = nullif(product->>'image_url',''),
      is_available = coalesce((product->>'is_available')::boolean, true),
      type = 'combo',
      contains = items::jsonb,
      updated_at = v_now
    where id = v_product_id
    returning id into v_product_id;
  end if;

  if v_product_id is null then
    raise exception 'No se pudo crear/actualizar el producto del combo';
  end if;

  -- Ensure product_combos row exists for this product
  select pc.id into v_combo_id from public.product_combos pc where pc.product_id = v_product_id;
  if v_combo_id is null then
    insert into public.product_combos (product_id, restaurant_id, created_at, updated_at)
    values (v_product_id, v_restaurant_id, v_now, v_now)
    returning id into v_combo_id;
  else
    update public.product_combos set updated_at = v_now where id = v_combo_id;
  end if;

  -- Replace items
  delete from public.product_combo_items pci where pci.combo_id = v_combo_id;

  insert into public.product_combo_items (combo_id, product_id, quantity, created_at, updated_at)
  select 
    v_combo_id,
    (e->>'product_id')::uuid,
    greatest(1, coalesce((e->>'quantity')::int, 1)) as quantity,
    v_now,
    v_now
  from jsonb_array_elements(items) e;

  -- Return payload
  select to_jsonb(p.*) into v_product_row from public.products p where p.id = v_product_id;
  select to_jsonb(c.*) into v_combo_row from public.product_combos c where c.id = v_combo_id;

  return jsonb_build_object('product', v_product_row, 'combo', v_combo_row);
exception when others then
  -- Surface meaningful error back to client
  raise;
end;
$$;

-- Permissions
grant execute on function public.upsert_combo_atomic(jsonb, jsonb, uuid) to anon, authenticated;
