-- =============================================
-- MIGRACIÓN: Agregar columna assigned_at a orders
-- =============================================

-- Agregar columna assigned_at para tracking cuando se asigna una orden al repartidor
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMP WITH TIME ZONE NULL;

-- Agregar comentario para documentación
COMMENT ON COLUMN orders.assigned_at IS 'Timestamp cuando la orden fue asignada a un repartidor';

-- Crear índice para optimizar consultas por fecha de asignación
CREATE INDEX IF NOT EXISTS idx_orders_assigned_at ON orders(assigned_at);

-- También vamos a asegurar que todas las columnas necesarias existan
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS pickup_time TIMESTAMP WITH TIME ZONE NULL,
ADD COLUMN IF NOT EXISTS delivery_fee DECIMAL(10,2) NULL;

-- Comentarios adicionales
COMMENT ON COLUMN orders.pickup_time IS 'Timestamp cuando el repartidor recogió la orden';
COMMENT ON COLUMN orders.delivery_fee IS 'Tarifa de entrega cobrada';

-- Crear índices para optimización
CREATE INDEX IF NOT EXISTS idx_orders_pickup_time ON orders(pickup_time);
CREATE INDEX IF NOT EXISTS idx_orders_delivery_fee ON orders(delivery_fee);