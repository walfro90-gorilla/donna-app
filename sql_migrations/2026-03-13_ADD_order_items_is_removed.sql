-- Agrega campo para marcar ítems quitados por la cocina sin eliminar el registro.
-- Permite enviar pedidos parciales cuando un producto no está disponible.
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS is_removed boolean NOT NULL DEFAULT false;

-- Índice parcial para filtrado rápido (solo indexa los quitados, que son minoría)
CREATE INDEX IF NOT EXISTS idx_order_items_is_removed
  ON public.order_items(is_removed)
  WHERE is_removed = true;
