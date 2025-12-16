-- ============================================================================
-- SCRIPT DE MIGRACIÓN COMPLETA: Flujo de Pago Mejorado
-- Fecha: 2025-01-17
-- ============================================================================
-- EJECUTAR EN: Supabase SQL Editor
-- 
-- PROPÓSITO:
--   Implementar el flujo correcto de pagos con MercadoPago:
--   
--   FLUJO ANTERIOR (INCORRECTO):
--   1. Crear orden en Supabase
--   2. Abrir MercadoPago
--   3. Si el usuario cancela → Orden huérfana en la BD ❌
--   
--   FLUJO NUEVO (CORRECTO):
--   1. Guardar datos del pedido en payment.order_data
--   2. Abrir MercadoPago
--   3. Usuario completa pago ✅
--   4. Webhook crea la orden con order_data
--   5. Webhook actualiza payment con order_id
-- ============================================================================

BEGIN;

-- Paso 1: Hacer order_id nullable (puede ser NULL hasta que el pago se confirme)
ALTER TABLE public.payments
ALTER COLUMN order_id DROP NOT NULL;

COMMENT ON COLUMN public.payments.order_id IS 'ID de la orden (NULL si la orden se crea después del pago)';

-- Paso 2: Añadir columna order_data para almacenar datos del pedido
ALTER TABLE public.payments
ADD COLUMN IF NOT EXISTS order_data JSONB DEFAULT NULL;

COMMENT ON COLUMN public.payments.order_data IS 'Datos de la orden (usuario, items, dirección, etc.) para crear orden tras pago exitoso. NULL si la orden ya existe.';

-- Paso 3: Crear índice GIN para búsquedas eficientes en order_data
CREATE INDEX IF NOT EXISTS idx_payments_order_data ON public.payments USING GIN (order_data);

-- Paso 4: Actualizar columna status para incluir 'completed'
ALTER TABLE public.payments
DROP CONSTRAINT IF EXISTS payments_status_check;

ALTER TABLE public.payments
ADD CONSTRAINT payments_status_check 
CHECK (status = ANY (ARRAY['pending'::text, 'succeeded'::text, 'failed'::text, 'completed'::text]));

COMMENT ON COLUMN public.payments.status IS 'Estado del pago: pending (inicial), completed (aprobado), failed (rechazado), succeeded (legacy)';

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT 
  column_name, 
  data_type, 
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'payments'
  AND column_name IN ('order_id', 'order_data', 'status')
ORDER BY ordinal_position;
