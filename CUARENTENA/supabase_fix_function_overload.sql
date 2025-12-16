-- ✅ SOLUCIÓN: Eliminar funciones duplicadas y crear una correcta
-- 🎯 Resuelve el error: "Could not choose the best candidate function"

-- PASO 1: Eliminar TODAS las versiones existentes de la función
DROP FUNCTION IF EXISTS public.update_order_with_tracking(text, text, text);
DROP FUNCTION IF EXISTS public.update_order_with_tracking(uuid, character varying, uuid);
DROP FUNCTION IF EXISTS public.update_order_with_tracking(uuid, text, uuid);

-- PASO 2: Crear una ÚNICA función con tipos consistentes
CREATE OR REPLACE FUNCTION public.update_order_with_tracking(
    order_uuid uuid,
    new_status text,
    updated_by_uuid uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result json;
    confirm_code_value text := null;
BEGIN
    -- Generar código de confirmación si el status es 'on_the_way'
    IF new_status = 'on_the_way' THEN
        confirm_code_value := LPAD(FLOOR(RANDOM() * 1000000)::text, 6, '0');
    END IF;
    
    -- Actualizar la orden
    UPDATE public.orders 
    SET 
        status = new_status,
        updated_at = NOW(),
        confirm_code = COALESCE(confirm_code_value, confirm_code)
    WHERE id = order_uuid;
    
    -- Insertar registro de seguimiento
    INSERT INTO public.order_status_updates (
        order_id,
        status,
        updated_by,
        created_at
    ) VALUES (
        order_uuid,
        new_status,
        updated_by_uuid,
        NOW()
    );
    
    -- Retornar resultado
    SELECT json_build_object(
        'success', true,
        'order_id', order_uuid,
        'new_status', new_status,
        'confirm_code', confirm_code_value,
        'updated_at', NOW()
    ) INTO result;
    
    RETURN result;
    
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$$;

-- PASO 3: Otorgar permisos
GRANT EXECUTE ON FUNCTION public.update_order_with_tracking(uuid, text, uuid) TO authenticated;

-- PASO 4: Verificar que la función fue creada correctamente
SELECT 
    proname as function_name,
    pg_get_function_arguments(oid) as arguments,
    pg_get_function_result(oid) as return_type
FROM pg_proc 
WHERE proname = 'update_order_with_tracking';

-- ✅ Mensaje de confirmación
DO $$
BEGIN
    RAISE NOTICE '✅ Función update_order_with_tracking recreada exitosamente';
    RAISE NOTICE '🎯 Tipos de parámetros: (uuid, text, uuid)';
    RAISE NOTICE '📋 Conflicto de sobrecarga resuelto';
END $$;