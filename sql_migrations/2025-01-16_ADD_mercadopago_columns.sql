-- ============================================================================
-- MIGRACIÓN: Agregar columnas de MercadoPago a tabla payments
-- FECHA: 2025-01-16
-- DESCRIPCIÓN: Agrega columnas necesarias para integración con MercadoPago
-- ============================================================================

-- ✅ AGREGAR COLUMNAS DE MERCADOPAGO
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS mp_preference_id TEXT,
  ADD COLUMN IF NOT EXISTS mp_payment_id TEXT,
  ADD COLUMN IF NOT EXISTS mp_init_point TEXT,
  ADD COLUMN IF NOT EXISTS payment_method TEXT CHECK (payment_method IN ('cash', 'card')) DEFAULT 'cash';

-- ✅ CREAR ÍNDICES PARA MEJORA DE PERFORMANCE
CREATE INDEX IF NOT EXISTS idx_payments_mp_preference_id ON public.payments(mp_preference_id);
CREATE INDEX IF NOT EXISTS idx_payments_mp_payment_id ON public.payments(mp_payment_id);
CREATE INDEX IF NOT EXISTS idx_payments_payment_method ON public.payments(payment_method);

-- ✅ COMENTARIOS PARA DOCUMENTACIÓN
COMMENT ON COLUMN public.payments.mp_preference_id IS 'ID de preferencia de pago generado por MercadoPago';
COMMENT ON COLUMN public.payments.mp_payment_id IS 'ID del pago en MercadoPago (cuando se complete)';
COMMENT ON COLUMN public.payments.mp_init_point IS 'URL de checkout de MercadoPago';
COMMENT ON COLUMN public.payments.payment_method IS 'Método de pago: cash (efectivo) o card (tarjeta)';
