-- Permitir a repartidores ver pedidos disponibles (no asignados) confirmados por el restaurante
-- Ejecutar en Supabase SQL Editor

DO $$
BEGIN
  -- Evitar duplicados si ya existe la política
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'orders'
      AND policyname = 'orders_select_available_for_delivery'
  ) THEN
    CREATE POLICY "orders_select_available_for_delivery" ON public.orders
      FOR SELECT USING (
        -- Solo usuarios con rol repartidor
        EXISTS (
          SELECT 1 FROM public.users u
          WHERE u.id = auth.uid() AND u.role = 'repartidor'
        )
        -- Y con pedido aún no asignado y aceptado por el restaurante
        AND delivery_agent_id IS NULL
        AND status IN ('confirmed', 'in_preparation', 'ready_for_pickup')
      );
  END IF;
END $$;

-- Nota: La tabla restaurants ya tiene SELECT abierto en políticas (restaurants_select_all)
-- por lo que los embeds de restaurant en la consulta funcionarán.
