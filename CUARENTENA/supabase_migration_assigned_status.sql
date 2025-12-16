-- ===============================================
-- MIGRACIÓN: Agregar estado 'assigned' a órdenes
-- ===============================================
-- Esta migración agrega el nuevo estado 'assigned' que se usa cuando un repartidor
-- acepta una orden pero aún no la ha recogido del restaurante.

-- Agregar el nuevo valor al enum de status (si es que se usa un enum)
-- Nota: Supabase no requiere enum estrictos, pero es buena práctica documentarlo

-- ===============================================
-- 1. ACTUALIZAR DOCUMENTACIÓN DEL SCHEMA
-- ===============================================

COMMENT ON COLUMN orders.status IS 'Estado de la orden: 
- pending: Esperando confirmación
- confirmed: Confirmado por restaurante
- in_preparation: En preparación
- ready_for_pickup: Listo para recoger
- assigned: Repartidor asignado, va al restaurante
- on_the_way: En camino al cliente
- delivered: Entregado
- canceled: Cancelado';

-- ===============================================
-- 2. CREAR ÍNDICE PARA OPTIMIZAR CONSULTAS POR STATUS
-- ===============================================

-- Índice para búsquedas por status (muy común en dashboards)
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);

-- Índice compuesto para órdenes activas por restaurante
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_active ON orders (restaurant_id, status)
WHERE status IN ('pending', 'confirmed', 'in_preparation', 'ready_for_pickup', 'assigned', 'on_the_way');

-- Índice compuesto para órdenes activas por usuario (cliente)
CREATE INDEX IF NOT EXISTS idx_orders_user_active ON orders (user_id, status)
WHERE status IN ('pending', 'confirmed', 'in_preparation', 'ready_for_pickup', 'assigned', 'on_the_way');

-- Índice para repartidores - órdenes asignadas
CREATE INDEX IF NOT EXISTS idx_orders_delivery_agent ON orders (delivery_agent_id, status)
WHERE delivery_agent_id IS NOT NULL;

-- ===============================================
-- 3. FUNCIÓN PARA VALIDAR TRANSICIONES DE ESTADO
-- ===============================================

-- Función que valida si una transición de estado es válida
CREATE OR REPLACE FUNCTION validate_order_status_transition(
    old_status TEXT,
    new_status TEXT
) RETURNS BOOLEAN AS $$
BEGIN
    -- Transiciones válidas
    RETURN CASE
        -- Desde pending
        WHEN old_status = 'pending' THEN new_status IN ('confirmed', 'canceled')
        -- Desde confirmed
        WHEN old_status = 'confirmed' THEN new_status IN ('in_preparation', 'canceled')
        -- Desde in_preparation
        WHEN old_status = 'in_preparation' THEN new_status IN ('ready_for_pickup', 'canceled')
        -- Desde ready_for_pickup
        WHEN old_status = 'ready_for_pickup' THEN new_status IN ('assigned', 'canceled')
        -- Desde assigned (nuevo estado)
        WHEN old_status = 'assigned' THEN new_status IN ('on_the_way', 'canceled')
        -- Desde on_the_way
        WHEN old_status = 'on_the_way' THEN new_status IN ('delivered', 'canceled')
        -- Estados finales
        WHEN old_status IN ('delivered', 'canceled') THEN FALSE
        -- Default: no permitir transición desconocida
        ELSE FALSE
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ===============================================
-- 4. TRIGGER PARA VALIDAR TRANSICIONES (OPCIONAL)
-- ===============================================

-- Función trigger para validar transiciones automáticamente
CREATE OR REPLACE FUNCTION check_order_status_transition() RETURNS TRIGGER AS $$
BEGIN
    -- Solo validar si el status cambió
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        -- Validar la transición
        IF NOT validate_order_status_transition(OLD.status, NEW.status) THEN
            RAISE EXCEPTION 'Transición de estado inválida: % -> %', OLD.status, NEW.status;
        END IF;
        
        -- Actualizar assigned_at cuando se asigna repartidor
        IF NEW.status = 'assigned' AND OLD.status != 'assigned' THEN
            NEW.assigned_at = NOW();
        END IF;
        
        -- Actualizar delivery_time cuando se entrega
        IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
            NEW.delivery_time = NOW();
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Aplicar el trigger (descomenta si quieres validación automática)
-- DROP TRIGGER IF EXISTS check_order_status_transition_trigger ON orders;
-- CREATE TRIGGER check_order_status_transition_trigger
--     BEFORE UPDATE ON orders
--     FOR EACH ROW
--     EXECUTE FUNCTION check_order_status_transition();

-- ===============================================
-- 5. ACTUALIZAR RLS POLICIES SI ES NECESARIO
-- ===============================================

-- Política para que los repartidores puedan ver órdenes asignadas a ellos
DROP POLICY IF EXISTS "repartidores_can_view_assigned_orders" ON orders;
CREATE POLICY "repartidores_can_view_assigned_orders" ON orders
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE users.id = auth.uid() 
            AND users.role = 'repartidor'
            AND users.id = orders.delivery_agent_id
        )
    );

-- Política para que los repartidores puedan actualizar órdenes asignadas
DROP POLICY IF EXISTS "repartidores_can_update_assigned_orders" ON orders;
CREATE POLICY "repartidores_can_update_assigned_orders" ON orders
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE users.id = auth.uid() 
            AND users.role = 'repartidor'
            AND users.id = orders.delivery_agent_id
        )
    );

-- ===============================================
-- DOCUMENTACIÓN
-- ===============================================

/*
NUEVO FLUJO DE ESTADOS CON 'assigned':

1. pending → confirmed (restaurante confirma)
2. confirmed → in_preparation (restaurante inicia preparación)
3. in_preparation → ready_for_pickup (restaurante termina preparación)
4. ready_for_pickup → assigned (repartidor acepta orden)
5. assigned → on_the_way (repartidor recoge orden)
6. on_the_way → delivered (repartidor entrega orden)

En cualquier momento antes de 'delivered': * → canceled

BENEFICIOS:
- Mejor tracking para clientes y restaurantes
- Información clara cuando repartidor está asignado
- Permite mostrar "repartidor va camino al restaurante"
- Mejora la experiencia de usuario con más transparencia
*/