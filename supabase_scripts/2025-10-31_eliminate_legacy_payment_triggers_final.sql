-- =============================================
-- ELIMINACIÓN QUIRÚRGICA DE TRIGGERS LEGACY
-- Ejecutar: 2025-10-31
-- =============================================
-- Problema: Múltiples triggers/funciones coexistiendo causan cálculo incorrecto de comisión
-- Solución: Eliminar TODO lo legacy y dejar solo process_order_payment_v2 con commission_bps dinámico

BEGIN;

-- ==========================================
-- 1) ELIMINAR TODOS LOS TRIGGERS LEGACY
-- ==========================================
DROP TRIGGER IF EXISTS trg_process_payments_on_delivery ON public.orders;
DROP TRIGGER IF EXISTS trigger_process_order_payment_final ON public.orders;
DROP TRIGGER IF EXISTS trigger_process_payment_on_delivery ON public.orders;
DROP TRIGGER IF EXISTS trigger_order_financial_completion ON public.orders;
DROP TRIGGER IF EXISTS trigger_process_order_payment ON public.orders;
DROP TRIGGER IF EXISTS trg_order_status_update ON public.orders;

-- ==========================================
-- 2) ELIMINAR TODAS LAS FUNCIONES LEGACY
-- ==========================================
DROP FUNCTION IF EXISTS public.process_payments_on_delivery() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment_final() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment_on_delivery() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment() CASCADE;

-- ==========================================
-- 3) RECREAR FUNCIÓN CANÓNICA V2
-- ==========================================
CREATE OR REPLACE FUNCTION public.process_order_payment_v2()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_commission_bps integer;
    v_commission_rate numeric(5,4);
    v_platform_commission numeric(10,2);
    v_restaurant_net numeric(10,2);
    v_delivery_earning numeric(10,2);
    v_platform_delivery_margin numeric(10,2);
    
    v_restaurant_account_id uuid;
    v_delivery_account_id uuid;
    v_platform_revenue_account_id uuid;
    v_platform_payables_account_id uuid;
    
    v_payment_method text;
BEGIN
    -- Solo procesar cuando cambia de cualquier estado a 'delivered'
    IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN
        
        -- ==========================================
        -- OBTENER COMMISSION_BPS DEL RESTAURANT
        -- ==========================================
        SELECT COALESCE(commission_bps, 1500) INTO v_commission_bps
        FROM public.restaurants
        WHERE id = NEW.restaurant_id;
        
        -- Clamp entre 0 y 3000 basis points (0% - 30%)
        v_commission_bps := GREATEST(0, LEAST(3000, v_commission_bps));
        
        -- Convertir a rate decimal (1500 bps = 0.1500 = 15%)
        v_commission_rate := v_commission_bps / 10000.0;
        
        -- ==========================================
        -- CALCULAR MONTOS
        -- ==========================================
        v_platform_commission := ROUND(NEW.subtotal * v_commission_rate, 2);
        v_restaurant_net := NEW.subtotal - v_platform_commission;
        v_delivery_earning := ROUND(NEW.delivery_fee * 0.85, 2);
        v_platform_delivery_margin := NEW.delivery_fee - v_delivery_earning;
        
        -- ==========================================
        -- OBTENER CUENTAS
        -- ==========================================
        -- Cuenta del restaurante
        SELECT id INTO v_restaurant_account_id
        FROM public.accounts
        WHERE user_id = (SELECT user_id FROM public.restaurants WHERE id = NEW.restaurant_id LIMIT 1)
        ORDER BY created_at DESC LIMIT 1;
        
        -- Cuenta del delivery
        SELECT id INTO v_delivery_account_id
        FROM public.accounts
        WHERE user_id = NEW.delivery_agent_id
        ORDER BY created_at DESC LIMIT 1;
        
        -- Cuentas de plataforma
        SELECT id INTO v_platform_revenue_account_id
        FROM public.accounts
        WHERE account_type = 'platform_revenue'
        ORDER BY created_at DESC LIMIT 1;
        
        SELECT id INTO v_platform_payables_account_id
        FROM public.accounts
        WHERE account_type = 'platform_payables'
        ORDER BY created_at DESC LIMIT 1;
        
        -- Método de pago
        SELECT payment_method INTO v_payment_method
        FROM public.payments
        WHERE order_id = NEW.id
        ORDER BY created_at DESC LIMIT 1;
        
        v_payment_method := COALESCE(v_payment_method, 'cash');
        
        -- ==========================================
        -- INSERTAR TRANSACCIONES CON METADATA
        -- ==========================================
        
        -- 1) Ingreso total de la orden
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata, payment_method
        ) VALUES (
            v_platform_payables_account_id,
            'ORDER_REVENUE',
            NEW.total,
            NEW.id,
            'Ingreso total de orden #' || NEW.id,
            jsonb_build_object(
                'commission_bps', v_commission_bps,
                'commission_rate', v_commission_rate,
                'subtotal', NEW.subtotal,
                'delivery_fee', NEW.delivery_fee
            ),
            v_payment_method
        );
        
        -- 2) Comisión de plataforma (ingreso)
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata, payment_method
        ) VALUES (
            v_platform_revenue_account_id,
            'PLATFORM_COMMISSION',
            v_platform_commission,
            NEW.id,
            'Comisión de plataforma (' || v_commission_bps || ' bps) - Orden #' || NEW.id,
            jsonb_build_object(
                'commission_bps', v_commission_bps,
                'commission_rate', v_commission_rate,
                'subtotal', NEW.subtotal,
                'calculated_commission', v_platform_commission
            ),
            v_payment_method
        );
        
        -- 3) Pago al restaurante
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata, payment_method
        ) VALUES (
            v_restaurant_account_id,
            'RESTAURANT_EARNING',
            v_restaurant_net,
            NEW.id,
            'Ingreso neto restaurante - Orden #' || NEW.id,
            jsonb_build_object(
                'commission_bps', v_commission_bps,
                'commission_rate', v_commission_rate,
                'subtotal', NEW.subtotal,
                'commission_deducted', v_platform_commission,
                'net_amount', v_restaurant_net
            ),
            v_payment_method
        );
        
        -- 4) Ganancia del delivery (85%)
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata, payment_method
        ) VALUES (
            v_delivery_account_id,
            'DELIVERY_EARNING',
            v_delivery_earning,
            NEW.id,
            'Ganancia por entrega (85% de delivery fee) - Orden #' || NEW.id,
            jsonb_build_object(
                'delivery_fee', NEW.delivery_fee,
                'delivery_percentage', 0.85,
                'calculated_earning', v_delivery_earning
            ),
            v_payment_method
        );
        
        -- 5) Margen de plataforma por delivery (15%)
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata, payment_method
        ) VALUES (
            v_platform_revenue_account_id,
            'PLATFORM_DELIVERY_MARGIN',
            v_platform_delivery_margin,
            NEW.id,
            'Margen de plataforma por delivery (15%) - Orden #' || NEW.id,
            jsonb_build_object(
                'delivery_fee', NEW.delivery_fee,
                'platform_percentage', 0.15,
                'calculated_margin', v_platform_delivery_margin
            ),
            v_payment_method
        );
        
        -- 6) Efectivo recolectado (negativo para balance cero)
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata, payment_method
        ) VALUES (
            v_platform_payables_account_id,
            'CASH_COLLECTED',
            -NEW.total,
            NEW.id,
            'Efectivo recolectado de orden #' || NEW.id,
            jsonb_build_object(
                'total', NEW.total,
                'collected_by_delivery', true
            ),
            v_payment_method
        );
        
        RAISE NOTICE '✅ Transacciones procesadas con commission_bps=%', v_commission_bps;
    END IF;
    
    RETURN NEW;
END;
$$;

-- ==========================================
-- 4) CREAR UN SOLO TRIGGER CANÓNICO
-- ==========================================
CREATE TRIGGER trigger_process_order_payment_v2_canonical
    AFTER UPDATE ON public.orders
    FOR EACH ROW
    WHEN (NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status IS DISTINCT FROM 'delivered'))
    EXECUTE FUNCTION public.process_order_payment_v2();

-- ==========================================
-- 5) VERIFICACIÓN
-- ==========================================
DO $$
DECLARE
    v_trigger_count integer;
    v_function_count integer;
BEGIN
    -- Contar triggers activos en orders relacionados con payment
    SELECT COUNT(*) INTO v_trigger_count
    FROM information_schema.triggers
    WHERE event_object_table = 'orders'
    AND trigger_name LIKE '%payment%';
    
    -- Contar funciones payment activas
    SELECT COUNT(*) INTO v_function_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
    AND p.proname LIKE '%payment%';
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ LIMPIEZA COMPLETADA';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Triggers payment activos: %', v_trigger_count;
    RAISE NOTICE 'Funciones payment activas: %', v_function_count;
    RAISE NOTICE '';
    RAISE NOTICE '📋 Debe quedar:';
    RAISE NOTICE '  - 1 trigger: trigger_process_order_payment_v2_canonical';
    RAISE NOTICE '  - 1 función: process_order_payment_v2()';
    RAISE NOTICE '';
    RAISE NOTICE '✅ La función ahora usa restaurants.commission_bps dinámicamente';
    RAISE NOTICE '✅ Todas las transacciones incluyen description + metadata';
END $$;

COMMIT;

-- ==========================================
-- INSTRUCCIONES POST-EJECUCIÓN
-- ==========================================
-- 1. Ejecutar este script en Supabase SQL Editor
-- 2. Verificar que solo aparece 1 trigger en la consulta:
--    SELECT trigger_name FROM information_schema.triggers 
--    WHERE event_object_table = 'orders' AND trigger_name LIKE '%payment%';
-- 3. Hacer una orden de prueba nueva
-- 4. Verificar en account_transactions que:
--    - description no sea NULL
--    - metadata no sea NULL
--    - PLATFORM_COMMISSION use el % correcto según restaurants.commission_bps
