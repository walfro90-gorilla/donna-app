-- RLS para product_combos y product_combo_items

BEGIN;

ALTER TABLE public.product_combos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_combo_items ENABLE ROW LEVEL SECURITY;

-- Lectura pública (para renderizar menús)
DROP POLICY IF EXISTS "product_combos_select_all" ON public.product_combos;
CREATE POLICY "product_combos_select_all" ON public.product_combos
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "product_combo_items_select_all" ON public.product_combo_items;
CREATE POLICY "product_combo_items_select_all" ON public.product_combo_items
  FOR SELECT USING (true);

-- Propietario del restaurante puede administrar combos
DROP POLICY IF EXISTS "product_combos_manage_own_restaurant" ON public.product_combos;
CREATE POLICY "product_combos_manage_own_restaurant" ON public.product_combos
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.products p
      JOIN public.restaurants r ON r.id = p.restaurant_id
      WHERE p.id = product_id AND r.user_id = auth.uid()
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.products p
      JOIN public.restaurants r ON r.id = p.restaurant_id
      WHERE p.id = product_id AND r.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "product_combo_items_manage_own_restaurant" ON public.product_combo_items;
CREATE POLICY "product_combo_items_manage_own_restaurant" ON public.product_combo_items
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.product_combos c
      JOIN public.products p ON p.id = c.product_id
      JOIN public.restaurants r ON r.id = p.restaurant_id
      WHERE c.id = combo_id AND r.user_id = auth.uid()
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.product_combos c
      JOIN public.products p ON p.id = c.product_id
      JOIN public.restaurants r ON r.id = p.restaurant_id
      WHERE c.id = combo_id AND r.user_id = auth.uid()
    )
  );

COMMIT;
