-- Agregar columna delivery_phone a la tabla orders
-- Ejecutar este script en Supabase SQL Editor

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS delivery_phone VARCHAR(20);

-- Comentario: Esta columna almacenará el teléfono de entrega para cada orden
COMMENT ON COLUMN orders.delivery_phone IS 'Número de teléfono para la entrega';

-- Verificar que la columna se agregó correctamente
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'orders' 
  AND column_name = 'delivery_phone';