-- =====================================================
-- 📋 AGREGAR COLUMNA CONFIRM_CODE A TABLA ORDERS
-- =====================================================

-- Agregar columna confirm_code a la tabla orders
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS confirm_code VARCHAR(6);

-- Crear índice para búsquedas rápidas del código
CREATE INDEX IF NOT EXISTS idx_orders_confirm_code 
ON orders(confirm_code);

-- Comentario explicativo
COMMENT ON COLUMN orders.confirm_code IS 'Código de 6 dígitos generado cuando el status cambia a on_the_way para confirmar entrega';

-- Verificar que la columna fue agregada exitosamente
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'orders' 
AND column_name = 'confirm_code';

-- Mostrar estructura actualizada de la tabla orders (solo campos relevantes)
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_name = 'orders'
ORDER BY ordinal_position;