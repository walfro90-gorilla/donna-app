-- ============================================================================
-- ADD: spei_codi como método de pago válido en orders.payment_method
-- Date: 2026-03-13
-- ============================================================================
-- Amplía el CHECK constraint para incluir 'spei_codi' (SPEI / CoDi bancario).
-- El valor 'spei_codi' aún no se usa en producción — este script solo prepara
-- la infraestructura de base de datos. Para activar el método de pago en la
-- app, descomentar PaymentMethod.spei_codi en:
--   lib/core/config/payment_config.dart
-- ============================================================================

-- Eliminar el CHECK constraint actual
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_payment_method_check;

-- Recrear incluyendo 'spei_codi'
ALTER TABLE public.orders
  ADD CONSTRAINT orders_payment_method_check
  CHECK (payment_method IN ('card', 'cash', 'spei_codi'));

-- Verificar:
-- SELECT conname, pg_get_constraintdef(oid)
-- FROM pg_constraint
-- WHERE conname = 'orders_payment_method_check';
-- Debe mostrar: payment_method IN ('card', 'cash', 'spei_codi')
