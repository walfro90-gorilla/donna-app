-- ==================================================
-- RPC FUNCTION: update_order_with_tracking
-- Implementación quirúrgica - Paso 1C
-- ==================================================

-- Función RPC para actualizar status con tracking atómico
CREATE OR REPLACE FUNCTION update_order_with_tracking(
    order_uuid UUID,
    new_status VARCHAR(50),
    updated_by_uuid UUID DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    -- 1. Actualizar el status en la tabla orders
    UPDATE public.orders 
    SET 
        status = new_status,
        updated_at = now(),
        -- Actualizar campos específicos según el status
        assigned_at = CASE 
            WHEN new_status = 'assigned' AND assigned_at IS NULL THEN now()
            ELSE assigned_at
        END,
        pickup_time = CASE 
            WHEN new_status = 'picked_up' AND pickup_time IS NULL THEN now()
            ELSE pickup_time
        END
    WHERE id = order_uuid;
    
    -- 2. Verificar que la orden existe
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order not found: %', order_uuid;
    END IF;
    
    -- 3. El trigger automático se encarga del insert en order_status_updates
    -- No necesitamos hacer insert manual, el trigger log_order_status_change lo hace
    
    -- 4. Log success
    RAISE NOTICE 'Order % status updated to % by %', order_uuid, new_status, updated_by_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Otorgar permisos
GRANT EXECUTE ON FUNCTION update_order_with_tracking(UUID, VARCHAR, UUID) TO authenticated;

COMMENT ON FUNCTION update_order_with_tracking(UUID, VARCHAR, UUID) IS 'Actualiza status de orden con tracking automático via trigger';