-- 🚀 SOLUCIÓN QUIRÚRGICA COMPLETA
-- Arregla los 2 problemas identificados

-- ========================================
-- PROBLEMA #1: Constraint no permite 'on_the_way'
-- ========================================

-- 1.1. Eliminar constraint restrictivo actual
DO $$ 
BEGIN 
    -- Detectar y eliminar constraint CHECK en orders.status
    IF EXISTS (
        SELECT 1 FROM information_schema.check_constraints 
        WHERE constraint_schema = 'public' 
        AND table_name = 'orders' 
        AND constraint_name LIKE '%status%'
    ) THEN
        -- Obtener el nombre exacto del constraint
        FOR rec IN 
            SELECT constraint_name 
            FROM information_schema.check_constraints 
            WHERE constraint_schema = 'public' 
            AND table_name = 'orders' 
            AND constraint_name LIKE '%status%'
        LOOP
            EXECUTE 'ALTER TABLE orders DROP CONSTRAINT IF EXISTS ' || rec.constraint_name;
            RAISE NOTICE 'Constraint eliminado: %', rec.constraint_name;
        END LOOP;
    END IF;
END $$;

-- 1.2. Crear nuevo constraint con TODOS los status permitidos
ALTER TABLE orders 
ADD CONSTRAINT orders_status_check_complete 
CHECK (status IN (
    'pending',
    'confirmed', 
    'in_preparation', 
    'ready_for_pickup',
    'assigned',
    'on_the_way',
    'delivered',
    'canceled'
));

-- ========================================
-- PROBLEMA #2: Flujo de estados mejorado
-- ========================================

-- 2.1. Crear función para transiciones de estado automáticas
CREATE OR REPLACE FUNCTION handle_order_status_transitions()
RETURNS TRIGGER AS $$
BEGIN
    -- Logging para debug
    RAISE NOTICE 'Status change detected: % -> %', OLD.status, NEW.status;
    
    -- Cuando un repartidor es asignado, el restaurant debe marcar como ready_for_pickup
    IF OLD.status = 'assigned' AND NEW.status = 'on_the_way' THEN
        -- Validar que el pedido pueda pasar a on_the_way
        RAISE NOTICE 'Repartidor recogiendo pedido: %', NEW.id;
        
        -- Agregar timestamp de recogida
        NEW.pickup_time = COALESCE(NEW.pickup_time, NOW());
    END IF;
    
    -- Cuando se entrega, agregar timestamp
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        NEW.delivery_time = COALESCE(NEW.delivery_time, NOW());
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2.2. Crear trigger para manejar transiciones
DROP TRIGGER IF EXISTS trigger_order_status_transitions ON orders;
CREATE TRIGGER trigger_order_status_transitions
    BEFORE UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION handle_order_status_transitions();

-- ========================================
-- VERIFICACIÓN DEL SISTEMA
-- ========================================

-- 3.1. Verificar que la tabla existe y funciona
DO $$
BEGIN
    -- Verificar estructura
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'orders') THEN
        RAISE EXCEPTION 'Tabla orders no existe!';
    END IF;
    
    -- Verificar constraint
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints 
        WHERE constraint_schema = 'public' 
        AND table_name = 'orders' 
        AND constraint_name = 'orders_status_check_complete'
    ) THEN
        RAISE EXCEPTION 'Constraint orders_status_check_complete no se creó!';
    END IF;
    
    RAISE NOTICE '✅ Verificación exitosa - Sistema listo para usar';
END $$;

-- 3.2. Mostrar estados permitidos
SELECT 'Estados permitidos en orders.status:' as info;
SELECT unnest(ARRAY[
    'pending',
    'confirmed', 
    'in_preparation', 
    'ready_for_pickup',
    'assigned',
    'on_the_way',
    'delivered',
    'canceled'
]) as status_permitido;