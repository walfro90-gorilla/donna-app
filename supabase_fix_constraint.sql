-- 🔧 FIX: Corrección del constraint orders_status_check
-- Este script corrige el constraint para incluir todos los valores válidos

-- 1. Primero, ver el constraint actual
SELECT 
    conname as constraint_name,
    pg_get_constraintdef(oid) as constraint_definition
FROM pg_constraint 
WHERE conname = 'orders_status_check';

-- 2. Eliminar constraint problemático si existe
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;

-- 3. Crear el constraint correcto con TODOS los valores válidos
ALTER TABLE orders ADD CONSTRAINT orders_status_check 
CHECK (status IN (
    'pending',
    'confirmed', 
    'preparing',
    'ready_for_pickup',
    'assigned',
    'picked_up',
    'in_transit',
    'delivered',
    'cancelled'
));

-- 4. Verificar que el constraint se creó correctamente
SELECT 
    conname as constraint_name,
    pg_get_constraintdef(oid) as constraint_definition
FROM pg_constraint 
WHERE conname = 'orders_status_check';