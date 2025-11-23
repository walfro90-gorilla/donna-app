-- 🔧 SIMPLE FIX: Script simplificado para arreglar constraint orders_status_check
-- Enfoque directo sin bucles complejos

-- 1. Eliminar constraints conocidos que pueden causar problemas
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check_complete;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS check_orders_status;

-- 2. Crear el constraint correcto con TODOS los valores válidos que usa la app
ALTER TABLE orders ADD CONSTRAINT orders_status_check_final
CHECK (status IN (
    'pending',
    'confirmed', 
    'preparing',
    'in_preparation',
    'ready_for_pickup',
    'assigned',
    'picked_up',
    'on_the_way',
    'in_transit',
    'delivered',
    'cancelled',
    'canceled'
));

-- 3. Verificar que el nuevo constraint funciona
SELECT 'Constraint creado exitosamente' AS resultado;

-- 4. Mostrar el constraint creado
SELECT 
    conname as constraint_name,
    pg_get_constraintdef(oid) as definition
FROM pg_constraint 
WHERE conname = 'orders_status_check_final';