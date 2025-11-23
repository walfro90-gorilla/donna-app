-- 🔧 CORRECCIÓN DE FUNCIÓN RPC update_order_with_tracking
-- Este script corrige la función que está causando el error de delivery_address_1

-- 1. Eliminar la función existente si existe
DROP FUNCTION IF EXISTS update_order_with_tracking(TEXT, TEXT, TEXT);

-- 2. Crear la función corregida
CREATE OR REPLACE FUNCTION update_order_with_tracking(
    order_uuid TEXT,
    new_status TEXT,
    updated_by_uuid TEXT
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Verificar que la orden existe
    IF NOT EXISTS (SELECT 1 FROM orders WHERE id = order_uuid::uuid) THEN
        RAISE EXCEPTION 'Order not found: %', order_uuid;
    END IF;

    -- Actualizar el status de la orden
    UPDATE orders 
    SET 
        status = new_status,
        updated_at = now()
    WHERE id = order_uuid::uuid;

    -- Registrar el cambio en order_status_updates
    INSERT INTO order_status_updates (
        id,
        order_id,
        old_status,
        new_status,
        updated_by,
        notes,
        created_at
    ) VALUES (
        gen_random_uuid(),
        order_uuid::uuid,
        (SELECT status FROM orders WHERE id = order_uuid::uuid),
        new_status,
        updated_by_uuid::uuid,
        'Status updated via update_order_with_tracking',
        now()
    );

    -- Log de éxito
    RAISE NOTICE 'Order % status updated to % by %', order_uuid, new_status, updated_by_uuid;
END;
$$;

-- 3. Otorgar permisos necesarios
GRANT EXECUTE ON FUNCTION update_order_with_tracking(TEXT, TEXT, TEXT) TO authenticated;

-- 4. Verificar que la función se creó correctamente
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.routines 
        WHERE routine_name = 'update_order_with_tracking' 
        AND routine_schema = 'public'
    ) THEN
        RAISE NOTICE '✅ Función update_order_with_tracking corregida exitosamente';
    ELSE
        RAISE EXCEPTION '❌ Error: La función no se creó correctamente';
    END IF;
END $$;