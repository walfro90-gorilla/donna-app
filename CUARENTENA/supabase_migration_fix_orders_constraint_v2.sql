-- ===============================================
-- MIGRACIÓN: Arreglar constraint de status en orders
-- Versión 2 - Compatible con PostgreSQL moderno
-- ===============================================

-- Primero, eliminamos el constraint existente
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;

-- Creamos el nuevo constraint con todos los status válidos incluido 'assigned'
ALTER TABLE orders ADD CONSTRAINT orders_status_check 
CHECK (status IN (
    'pending',
    'confirmed', 
    'preparing',
    'ready_for_pickup',
    'assigned',
    'in_delivery', 
    'delivered',
    'cancelled'
));

-- Verificamos que el constraint se aplicó correctamente
SELECT 
    con.conname AS constraint_name,
    pg_get_constraintdef(con.oid) AS constraint_definition
FROM pg_constraint con
INNER JOIN pg_class rel ON rel.oid = con.conrelid
WHERE rel.relname = 'orders' 
AND con.contype = 'c'
AND con.conname = 'orders_status_check';

-- Mensaje de confirmación
SELECT 'Constraint orders_status_check actualizado exitosamente con status: assigned' AS resultado;