-- ==================================================
-- MIGRACIÓN: Tabla order_status_updates y triggers
-- Implementación quirúrgica - Paso 1A
-- ==================================================

-- 1. Crear tabla order_status_updates
CREATE TABLE IF NOT EXISTS public.order_status_updates (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL,
    updated_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- 2. Índices para performance
CREATE INDEX IF NOT EXISTS idx_order_status_updates_order_id ON public.order_status_updates(order_id);
CREATE INDEX IF NOT EXISTS idx_order_status_updates_created_at ON public.order_status_updates(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_status_updates_status ON public.order_status_updates(status);

-- 3. RLS Policies
ALTER TABLE public.order_status_updates ENABLE ROW LEVEL SECURITY;

-- Policy: Usuarios pueden ver updates de sus órdenes relacionadas
CREATE POLICY "Users can view their order status updates" ON public.order_status_updates
    FOR SELECT USING (
        order_id IN (
            SELECT id FROM public.orders 
            WHERE user_id = auth.uid() 
            OR restaurant_id IN (
                SELECT id FROM public.restaurants WHERE user_id = auth.uid()
            )
            OR delivery_agent_id = auth.uid()
        )
    );

-- Policy: Solo sistema puede insertar (para triggers automáticos)
CREATE POLICY "System can insert order status updates" ON public.order_status_updates
    FOR INSERT WITH CHECK (true);

-- 4. Función para logging de cambios de status
CREATE OR REPLACE FUNCTION log_order_status_change()
RETURNS TRIGGER AS $$
BEGIN
    -- Solo insertar si el status realmente cambió
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO public.order_status_updates (
            order_id,
            status,
            updated_by,
            metadata
        ) VALUES (
            NEW.id,
            NEW.status,
            COALESCE(NEW.delivery_agent_id, NEW.restaurant_id, NEW.user_id),
            jsonb_build_object(
                'previous_status', COALESCE(OLD.status, 'new'),
                'updated_at', now(),
                'trigger_source', 'order_update'
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Trigger para logging automático
DROP TRIGGER IF EXISTS trigger_log_order_status_change ON public.orders;
CREATE TRIGGER trigger_log_order_status_change
    AFTER UPDATE ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION log_order_status_change();

-- 6. Poblar tabla con órdenes existentes (solo una vez)
INSERT INTO public.order_status_updates (order_id, status, created_at, metadata)
SELECT 
    id,
    status,
    created_at,
    jsonb_build_object(
        'initial_import', true,
        'imported_at', now()
    )
FROM public.orders
WHERE id NOT IN (SELECT DISTINCT order_id FROM public.order_status_updates);

-- 7. Función helper para obtener último status
CREATE OR REPLACE FUNCTION get_latest_order_status(order_uuid UUID)
RETURNS TABLE (
    status VARCHAR(50),
    updated_at TIMESTAMPTZ,
    updated_by UUID
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        osu.status,
        osu.created_at,
        osu.updated_by
    FROM public.order_status_updates osu
    WHERE osu.order_id = order_uuid
    ORDER BY osu.created_at DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON TABLE public.order_status_updates IS 'Historial de cambios de estado de órdenes con timestamps precisos';
COMMENT ON FUNCTION log_order_status_change() IS 'Trigger function que registra automáticamente cambios de status';
COMMENT ON FUNCTION get_latest_order_status(UUID) IS 'Helper para obtener el último status de una orden específica';