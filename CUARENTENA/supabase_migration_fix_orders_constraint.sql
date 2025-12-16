-- =========================================
-- MIGRACIÓN: ARREGLAR CHECK CONSTRAINT DE ORDERS
-- =========================================
-- Problema: El constraint orders_status_check no permite el status 'assigned'
-- Solución: Actualizar el constraint para incluir todos los status válidos

-- 1. Eliminar el constraint actual
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;

-- 2. Crear el nuevo constraint con todos los status válidos incluyendo 'assigned'
ALTER TABLE orders ADD CONSTRAINT orders_status_check 
    CHECK (status IN (
        'pending',
        'confirmed', 
        'in_preparation',
        'ready_for_pickup',
        'assigned',        -- ✅ NUEVO STATUS AGREGADO
        'on_the_way',
        'delivered',
        'canceled'
    ));

-- 3. Verificar que el constraint fue creado correctamente
SELECT conname, consrc 
FROM pg_constraint 
WHERE conrelid = 'orders'::regclass 
AND conname = 'orders_status_check';

-- ========================================= 
-- COMENTARIOS:
-- - Esta migración permite que el repartidor pueda aceptar órdenes 
--   sin que Supabase rechace el status 'assigned'
-- - El status 'assigned' se usa cuando el repartidor acepta una orden
--   pero aún no ha llegado al restaurante para recogerla
-- =========================================