-- =====================================================
-- 🚨 SOLUCIÓN CRÍTICA: Crear función RPC faltante
-- =====================================================
-- Esta función es requerida por OrderStatusHelper.dart
-- El error 404 indica que no existe en Supabase

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
    
    -- 3. Insertar registro de tracking en order_status_updates
    INSERT INTO public.order_status_updates (
        order_id, 
        status, 
        updated_by_user_id, 
        created_at
    ) VALUES (
        order_uuid, 
        new_status, 
        updated_by_uuid, 
        now()
    );
    
    -- 4. Log success
    RAISE NOTICE 'Order % status updated to % by %', order_uuid, new_status, updated_by_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Otorgar permisos a usuarios autenticados
GRANT EXECUTE ON FUNCTION update_order_with_tracking(UUID, VARCHAR, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_order_with_tracking(UUID, VARCHAR, UUID) TO anon;

-- Verificar que la función se creó correctamente
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.routines 
        WHERE routine_name = 'update_order_with_tracking'
        AND routine_schema = 'public'
    ) THEN
        RAISE NOTICE '✅ Función update_order_with_tracking creada exitosamente';
    ELSE
        RAISE EXCEPTION '❌ Error: La función no se creó correctamente';
    END IF;
END $$;