-- ============================================================================
-- MIGRACIÓN: Hacer order_id nullable en tabla payments
-- Fecha: 2025-01-17
-- Descripción: 
--   Permite que order_id sea NULL en payments para el flujo:
--   1. Se crea payment con order_data (sin order_id)
--   2. Usuario paga en MercadoPago
--   3. Webhook recibe confirmación
--   4. Webhook crea orden usando order_data
--   5. Webhook actualiza payment con order_id
-- ============================================================================

-- Quitar la restricción NOT NULL de order_id
ALTER TABLE public.payments
ALTER COLUMN order_id DROP NOT NULL;

-- Comentario descriptivo
COMMENT ON COLUMN public.payments.order_id IS 'ID de la orden (puede ser NULL si la orden se crea después del pago)';
