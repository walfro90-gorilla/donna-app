-- 🔧 FIX: Script corregido para arreglar constraint orders_status_check
-- Este script corrige la sintaxis del bucle FOR y añade todos los valores válidos

-- 1. Eliminar constraint problemático si existe
DO $$ 
DECLARE 
    constraint_rec RECORD;
BEGIN 
    -- Detectar y eliminar constraint CHECK en orders.status
    FOR constraint_rec IN 
        SELECT constraint_name 
        FROM information_schema.check_constraints 
        WHERE constraint_schema = 'public' 
        AND table_name = 'orders' 
        AND constraint_name LIKE '%status%'
    LOOP
        EXECUTE format('ALTER TABLE orders DROP CONSTRAINT IF EXISTS %I', constraint_rec.constraint_name);
        RAISE NOTICE 'Constraint eliminado: %', constraint_rec.constraint_name;
    END LOOP;
END $$;

-- 2. Crear el constraint correcto con TODOS los valores válidos
ALTER TABLE orders ADD CONSTRAINT orders_status_check_complete
CHECK (status IN (
    'pending',
    'confirmed', 
    'in_preparation',
    'ready_for_pickup',
    'assigned',
    'on_the_way',
    'picked_up',
    'in_transit',
    'delivered',
    'cancelled',
    'canceled'
));

-- 3. Verificar que el constraint se creó correctamente
SELECT 
    conname as constraint_name,
    pg_get_constraintdef(oid) as constraint_definition
FROM pg_constraint 
WHERE conname = 'orders_status_check_complete';

-- 4. Mensaje de confirmación
SELECT '✅ Constraint orders_status_check_complete creado exitosamente' AS resultado;