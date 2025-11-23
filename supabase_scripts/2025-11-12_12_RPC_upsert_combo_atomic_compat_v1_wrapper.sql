-- =============================================================================
-- 2025-11-12_12_RPC_upsert_combo_atomic_compat_v1_wrapper.sql
-- Wrapper de compatibilidad para mantener la firma antigua:
--   upsert_combo_atomic(product jsonb, items jsonb, product_id uuid)
-- Devuelve el mismo shape anterior: { product: {...}, combo: {...} }
-- Internamente delega a la nueva función v2 (con firma explícita) y
-- recompone el payload antiguo para no romper el cliente.
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
  v_res jsonb;
  v_pid uuid;
  v_cid uuid;
  v_product_row jsonb;
  v_combo_row jsonb;
BEGIN
  -- Delegar a la nueva versión con firma explícita
  v_res := public.upsert_combo_atomic(
    product_id,
    (product->>'restaurant_id')::uuid,
    nullif(product->>'name',''),
    nullif(product->>'description',''),
    (product->>'price')::numeric,
    nullif(product->>'image_url',''),
    COALESCE((product->>'is_available')::boolean, TRUE),
    items
  );

  -- Recuperar filas completas para devolver el mismo shape antiguo
  v_pid := (v_res->>'product_id')::uuid;
  v_cid := (v_res->>'combo_id')::uuid;

  SELECT to_jsonb(p.*) INTO v_product_row FROM public.products p WHERE p.id = v_pid;
  SELECT to_jsonb(c.*) INTO v_combo_row FROM public.product_combos c WHERE c.id = v_cid;

  RETURN jsonb_build_object('product', v_product_row, 'combo', v_combo_row);
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_combo_atomic(jsonb, jsonb, uuid) TO anon, authenticated;

COMMENT ON FUNCTION public.upsert_combo_atomic(jsonb, jsonb, uuid) IS 'Wrapper de compatibilidad: mantiene la firma y respuesta antiguas, delegando a la nueva implementación.';
