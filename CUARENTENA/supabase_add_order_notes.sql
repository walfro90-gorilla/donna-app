-- 📝 Agregar columna order_notes a la tabla orders
-- Ejecutar en Supabase Dashboard > SQL Editor

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS order_notes TEXT;

-- Comentario para la columna
COMMENT ON COLUMN orders.order_notes IS 'Notas opcionales del cliente para el pedido';

-- Confirmar que la columna se agregó correctamente
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'orders' AND column_name = 'order_notes';