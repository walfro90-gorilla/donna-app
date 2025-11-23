-- ============================================================================
-- MIGRACIÓN: Añadir columna order_data a tabla payments
-- Fecha: 2025-01-17
-- Descripción: 
--   Añade la columna 'order_data' (JSONB) a la tabla payments para almacenar
--   los datos necesarios para crear la orden después de un pago exitoso.
--   Esto permite el flujo: Pago primero → Webhook crea orden
-- ============================================================================

-- Añadir columna order_data como JSONB (puede ser NULL si la orden ya existe)
ALTER TABLE public.payments
ADD COLUMN IF NOT EXISTS order_data JSONB DEFAULT NULL;

-- Índice para búsquedas eficientes en order_data
CREATE INDEX IF NOT EXISTS idx_payments_order_data ON public.payments USING GIN (order_data);

-- Comentario descriptivo
COMMENT ON COLUMN public.payments.order_data IS 'Datos de la orden (usuario, items, dirección, etc.) para crear orden tras pago exitoso. NULL si la orden ya existe.';
