-- Agrega campo para marcar ítems quitados por la cocina sin eliminar el registro.
-- Permite enviar pedidos parciales cuando un producto no está disponible.
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS is_removed boolean NOT NULL DEFAULT false;

-- Índice parcial para filtrado rápido (solo indexa los quitados, que son minoría)
CREATE INDEX IF NOT EXISTS idx_order_items_is_removed
  ON public.order_items(is_removed)
  WHERE is_removed = true;

-- RLS: permite que el dueño del restaurante marque ítems como quitados
-- (sin esto el UPDATE silently falla con 0 rows y el cambio no persiste en DB)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'order_items'
      AND policyname = 'restaurants_can_remove_order_items'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY restaurants_can_remove_order_items
      ON public.order_items
      FOR UPDATE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.orders o
          JOIN public.restaurants r ON r.id = o.restaurant_id
          WHERE o.id = order_items.order_id
            AND r.user_id = auth.uid()
        )
      )
      WITH CHECK (true);
    $policy$;
  END IF;
END;
$$;
