-- Eliminar funciones existentes para evitar conflictos
DROP FUNCTION IF EXISTS insert_order_items CASCADE;
DROP FUNCTION IF EXISTS create_order_safe CASCADE;

-- Limpiar cualquier función duplicada con diferentes firmas
DROP FUNCTION IF EXISTS insert_order_items(UUID, JSONB) CASCADE;
DROP FUNCTION IF EXISTS create_order_safe(UUID, UUID, DECIMAL, TEXT, DECIMAL, TEXT, TEXT) CASCADE;