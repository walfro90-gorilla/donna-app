-- ============================================================================
-- 🗑️ ADMIN: DELETE USER RPC
-- ============================================================================
-- Objetivo: Permitir a los administradores eliminar o "soft-delete" usuarios.
-- Estrategia:
-- 1. Si el usuario tiene PEDIDOS ACTIVOS -> Error (No se puede eliminar).
-- 2. Si el usuario tiene HISTORIAL (pedidos pasados) -> Soft Delete (Anonymize).
-- 3. Si el usuario NO tiene historial -> Hard Delete (Eliminación total).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_admin_delete_user(
    p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER -- Ejecutar con permisos de sistema (Bypass RLS)
AS $$
DECLARE
    v_active_orders_count int;
    v_total_orders_count int;
    v_user_email text;
    v_result text;
BEGIN
    -- 1. Verificar si quien llama es ADMIN
    IF NOT EXISTS (
        SELECT 1 FROM public.users 
        WHERE id = auth.uid() AND role = 'admin'
    ) THEN
        RETURN jsonb_build_object('success', false, 'message', 'Acceso denegado: Requiere rol de admin');
    END IF;

    -- 2. Obtener datos del usuario objetivo
    SELECT email INTO v_user_email FROM public.users WHERE id = p_user_id;
    IF v_user_email IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Usuario no encontrado');
    END IF;

    -- 3. Verificar Pedidos Activos
    SELECT COUNT(*) INTO v_active_orders_count
    FROM public.orders
    WHERE user_id = p_user_id 
      AND status NOT IN ('delivered', 'cancelled', 'canceled', 'not_delivered');

    IF v_active_orders_count > 0 THEN
        RETURN jsonb_build_object(
            'success', false, 
            'message', 'No se puede eliminar: El usuario tiene ' || v_active_orders_count || ' pedidos activos.'
        );
    END IF;

    -- 4. Verificar Historial Completo
    SELECT COUNT(*) INTO v_total_orders_count
    FROM public.orders
    WHERE user_id = p_user_id;

    -- 5. Ejecutar Eliminación
    IF v_total_orders_count > 0 THEN
        -- A) SOFT DELETE (Tiene historial, mantenemos integridad referencial pero anonimizamos)
        -- Renombrar email para liberar el original y "borrar" datos personales
        UPDATE public.users
        SET 
            email = 'deleted_' || floor(extract(epoch from now())) || '_' || substring(id::text from 1 for 8) || '@void.dona',
            name = 'Usuario Eliminado',
            phone = NULL,
            email_confirm = false,
            updated_at = now()
        WHERE id = p_user_id;

        -- Actualizar perfil
        UPDATE public.client_profiles
        SET 
            status = 'inactive',
            profile_image_url = NULL,
            address = NULL,
            address_structured = NULL
        WHERE user_id = p_user_id;

        v_result := 'soft_deleted';
    ELSE
        -- B) HARD DELETE (Sin historial, borrón y cuenta nueva)
        -- Eliminar dependencias primero (si no hay CASCADE configurado)
        DELETE FROM public.client_profiles WHERE user_id = p_user_id;
        DELETE FROM public.user_preferences WHERE user_id = p_user_id;
        DELETE FROM public.accounts WHERE user_id = p_user_id; -- Cuidado si hay transacciones
        DELETE FROM public.delivery_agent_profiles WHERE user_id = p_user_id;
        DELETE FROM public.restaurants WHERE user_id = p_user_id;
        
        -- Finalmente eliminar usuario
        DELETE FROM public.users WHERE id = p_user_id;
        
        v_result := 'hard_deleted';
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'action', v_result,
        'message', CASE 
            WHEN v_result = 'soft_deleted' THEN 'Usuario desactivado y anonimizado (con historial).'
            ELSE 'Usuario eliminado permanentemente (sin historial).'
        END
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'message', 'Error interno: ' || SQLERRM);
END;
$$;
