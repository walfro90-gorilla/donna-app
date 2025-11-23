-- Mejoras a la tabla de pagos para procesamiento con tarjeta
-- Ejecutar en Supabase SQL Editor

-- 1. Agregar índice para búsquedas rápidas por mp_payment_id
CREATE INDEX IF NOT EXISTS idx_payments_mp_payment_id 
ON payments(mp_payment_id) 
WHERE mp_payment_id IS NOT NULL;

-- 2. Agregar índice compuesto para búsquedas por orden y estado
CREATE INDEX IF NOT EXISTS idx_payments_order_status 
ON payments(order_id, status);

-- 3. Agregar constraint para asegurar que mp_payment_id sea único cuando existe
CREATE UNIQUE INDEX IF NOT EXISTS unique_mp_payment_id 
ON payments(mp_payment_id) 
WHERE mp_payment_id IS NOT NULL;

-- 4. Agregar función para validar montos de pago
CREATE OR REPLACE FUNCTION validate_payment_amount()
RETURNS TRIGGER AS $$
BEGIN
  -- Validar que el monto sea positivo
  IF NEW.amount <= 0 THEN
    RAISE EXCEPTION 'El monto del pago debe ser positivo';
  END IF;
  
  -- Validar que client_debt_amount no sea negativo
  IF NEW.client_debt_amount < 0 THEN
    RAISE EXCEPTION 'El monto de deuda del cliente no puede ser negativo';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5. Aplicar trigger de validación
DROP TRIGGER IF EXISTS validate_payment_amount_trigger ON payments;
CREATE TRIGGER validate_payment_amount_trigger
BEFORE INSERT OR UPDATE ON payments
FOR EACH ROW
EXECUTE FUNCTION validate_payment_amount();

-- 6. Comentarios en columnas para documentación
COMMENT ON COLUMN payments.mp_payment_id IS 'ID del pago en MercadoPago (debe ser único)';
COMMENT ON COLUMN payments.payment_provider_id IS 'ID genérico del proveedor de pagos';
COMMENT ON COLUMN payments.client_debt_amount IS 'Monto de deuda del cliente pagada en esta transacción';
COMMENT ON COLUMN payments.payment_details IS 'Detalles adicionales del pago (JSON): payment_method_id, installments, status_detail, etc.';
