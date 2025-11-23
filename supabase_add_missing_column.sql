-- ========================================
-- FIX: Agregar columna faltante updated_by_user_id
-- ========================================

-- 1. Agregar la columna faltante a order_status_updates
ALTER TABLE order_status_updates 
ADD COLUMN IF NOT EXISTS updated_by_user_id UUID REFERENCES users(id);

-- 2. Crear índice para mejorar performance
CREATE INDEX IF NOT EXISTS idx_order_status_updates_updated_by_user_id 
ON order_status_updates(updated_by_user_id);

-- 3. Verificar que la función RPC existe y funciona correctamente
CREATE OR REPLACE FUNCTION update_order_with_tracking(
    p_order_id UUID,
    p_new_status TEXT,
    p_updated_by_user_id UUID DEFAULT NULL
) RETURNS JSON AS $$
DECLARE
    v_result JSON;
BEGIN
    -- Actualizar la orden
    UPDATE orders 
    SET status = p_new_status, 
        updated_at = NOW()
    WHERE id = p_order_id;
    
    -- Insertar en order_status_updates para tracking
    INSERT INTO order_status_updates (
        order_id, 
        status, 
        updated_by_user_id,
        created_at
    ) VALUES (
        p_order_id, 
        p_new_status, 
        p_updated_by_user_id,
        NOW()
    );
    
    -- Retornar resultado
    SELECT json_build_object(
        'success', true,
        'order_id', p_order_id,
        'new_status', p_new_status
    ) INTO v_result;
    
    RETURN v_result;
    
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Verificar estructura final de la tabla
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'order_status_updates' 
AND table_schema = 'public'
ORDER BY ordinal_position;