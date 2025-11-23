-- ============================================================================
-- FIX: Buscar cuentas de plataforma por EMAIL en lugar de role
-- ============================================================================
-- PROBLEMA: El trigger busca platform_revenue/platform_payables usando:
--           WHERE u.role = 'platform' AND a.account_type = 'platform_revenue'
--           pero esto falla porque el usuario puede no tener role='platform'.
--           
-- SOLUCIÓN: Buscar directamente por el email del usuario de plataforma
--           (platform+revenue@doarepartos.com) que es único y estable.
-- ============================================================================

-- Paso 1: DROP función y trigger existente
DROP TRIGGER IF EXISTS trg_auto_process_payment_on_delivery ON public.orders;
DROP FUNCTION IF EXISTS public.process_order_payment_on_delivery() CASCADE;

-- Paso 2: Crear función CORRECTA buscando por EMAIL
CREATE OR REPLACE FUNCTION public.process_order_payment_on_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_restaurant_account_id uuid;
    v_delivery_account_id uuid;
    v_platform_revenue_account_id uuid;
    v_platform_payables_account_id uuid;
    
    v_commission_bps integer;
    v_commission_rate numeric(10,4);
    v_platform_commission numeric(10,2);
    v_restaurant_net numeric(10,2);
    v_delivery_earning numeric(10,2);
    v_platform_delivery_margin numeric(10,2);
    
    v_payment_method text;
BEGIN
    -- Solo procesar cuando cambia de cualquier estado a 'delivered'
    IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN
        
        -- ==========================================
        -- OBTENER CUENTAS NECESARIAS
        -- ==========================================
        
        -- Cuenta del restaurante
        SELECT a.id INTO v_restaurant_account_id
        FROM public.accounts a
        INNER JOIN public.restaurants r ON r.user_id = a.user_id
        WHERE r.id = NEW.restaurant_id
        AND a.account_type = 'restaurant'
        ORDER BY a.created_at DESC LIMIT 1;
        
        -- Cuenta del delivery agent
        SELECT id INTO v_delivery_account_id
        FROM public.accounts
        WHERE user_id = NEW.delivery_agent_id
        AND account_type = 'delivery_agent'
        ORDER BY created_at DESC LIMIT 1;
        
        -- ✅ BUSCAR platform_revenue POR EMAIL (no por role)
        SELECT a.id INTO v_platform_revenue_account_id
        FROM public.accounts a
        INNER JOIN public.users u ON u.id = a.user_id
        WHERE u.email LIKE 'platform+revenue%'
        AND a.account_type = 'platform_revenue'
        ORDER BY a.created_at DESC LIMIT 1;
        
        -- ✅ BUSCAR platform_payables POR EMAIL (no por role)
        SELECT a.id INTO v_platform_payables_account_id
        FROM public.accounts a
        INNER JOIN public.users u ON u.id = a.user_id
        WHERE u.email LIKE 'platform+payables%'
        AND a.account_type = 'platform_payables'
        ORDER BY a.created_at DESC LIMIT 1;
        
        -- Validaciones
        IF v_restaurant_account_id IS NULL THEN
            RAISE EXCEPTION 'Restaurant account not found for restaurant_id=%', NEW.restaurant_id;
        END IF;
        
        IF v_delivery_account_id IS NULL THEN
            RAISE EXCEPTION 'Delivery agent account not found for delivery_agent_id=%', NEW.delivery_agent_id;
        END IF;
        
        IF v_platform_revenue_account_id IS NULL THEN
            RAISE EXCEPTION 'Platform revenue account not found (searched for email LIKE platform+revenue%%)';
        END IF;
        
        IF v_platform_payables_account_id IS NULL THEN
            RAISE EXCEPTION 'Platform payables account not found (searched for email LIKE platform+payables%%)';
        END IF;
        
        -- ==========================================
        -- CALCULAR COMISIÓN DINÁMICA
        -- ==========================================
        
        -- Obtener commission_bps desde restaurants
        SELECT commission_bps INTO v_commission_bps
        FROM public.restaurants
        WHERE id = NEW.restaurant_id;
        
        v_commission_bps := COALESCE(v_commission_bps, 1500); -- Default 15%
        v_commission_bps := LEAST(GREATEST(v_commission_bps, 0), 3000); -- Clamp 0-30%
        
        v_commission_rate := v_commission_bps / 10000.0;
        v_platform_commission := ROUND((NEW.subtotal * v_commission_rate)::numeric, 2);
        v_restaurant_net := NEW.subtotal - v_platform_commission;
        
        -- Delivery earnings: 85% del fee
        v_delivery_earning := ROUND((COALESCE(NEW.delivery_fee, 0) * 0.85)::numeric, 2);
        v_platform_delivery_margin := COALESCE(NEW.delivery_fee, 0) - v_delivery_earning;
        
        -- Leer payment_method desde orders
        v_payment_method := COALESCE(NEW.payment_method, 'cash');
        
        -- ==========================================
        -- INSERTAR TRANSACCIONES CON METADATA
        -- ==========================================
        
        -- 1) Ingreso total de la orden (platform_payables recibe el dinero)
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata
        ) VALUES (
            v_platform_payables_account_id,
            'ORDER_REVENUE',
            NEW.total_amount,
            NEW.id,
            'Ingreso total pedido #' || NEW.id::text,
            jsonb_build_object(
                'order_id', NEW.id,
                'payment_method', v_payment_method,
                'restaurant_id', NEW.restaurant_id,
                'subtotal', NEW.subtotal,
                'delivery_fee', NEW.delivery_fee
            )
        );
        
        -- 2) Comisión de plataforma (ingreso a platform_revenue)
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata
        ) VALUES (
            v_platform_revenue_account_id,
            'PLATFORM_COMMISSION',
            v_platform_commission,
            NEW.id,
            'Comisión plataforma (' || (v_commission_rate * 100)::text || '%) pedido #' || NEW.id::text,
            jsonb_build_object(
                'order_id', NEW.id,
                'commission_bps', v_commission_bps,
                'commission_rate', v_commission_rate,
                'subtotal', NEW.subtotal,
                'calculated_commission', v_platform_commission
            )
        );
        
        -- 3) Pago al restaurante (neto después de comisión)
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata
        ) VALUES (
            v_restaurant_account_id,
            'RESTAURANT_PAYABLE',
            v_restaurant_net,
            NEW.id,
            'Pago neto restaurante pedido #' || NEW.id::text,
            jsonb_build_object(
                'order_id', NEW.id,
                'subtotal', NEW.subtotal,
                'commission_bps', v_commission_bps,
                'commission_deducted', v_platform_commission,
                'net_amount', v_restaurant_net
            )
        );
        
        -- 4) Ganancia del delivery (85% del fee)
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata
        ) VALUES (
            v_delivery_account_id,
            'DELIVERY_EARNING',
            v_delivery_earning,
            NEW.id,
            'Ganancia delivery (85%) pedido #' || NEW.id::text,
            jsonb_build_object(
                'order_id', NEW.id,
                'delivery_fee', NEW.delivery_fee,
                'delivery_percentage', 0.85,
                'calculated_earning', v_delivery_earning
            )
        );
        
        -- 5) Margen de plataforma por delivery (15% del fee)
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata
        ) VALUES (
            v_platform_revenue_account_id,
            'PLATFORM_DELIVERY_MARGIN',
            v_platform_delivery_margin,
            NEW.id,
            'Margen plataforma delivery (15%) pedido #' || NEW.id::text,
            jsonb_build_object(
                'order_id', NEW.id,
                'delivery_fee', NEW.delivery_fee,
                'platform_percentage', 0.15,
                'calculated_margin', v_platform_delivery_margin
            )
        );
        
        -- 6) Balance cero: efectivo recolectado (negativo en platform_payables)
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata
        ) VALUES (
            v_platform_payables_account_id,
            'CASH_COLLECTED',
            -NEW.total_amount,
            NEW.id,
            'Efectivo recolectado pedido #' || NEW.id::text,
            jsonb_build_object(
                'order_id', NEW.id,
                'total', NEW.total_amount,
                'collected_by_delivery', true
            )
        );
        
        RAISE NOTICE '✅ Payment processing completed for order %', NEW.id;
        
    END IF;
    
    RETURN NEW;
END;
$$;

-- Paso 3: Crear trigger
CREATE TRIGGER trg_auto_process_payment_on_delivery
AFTER UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.process_order_payment_on_delivery();

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
-- Para verificar que los accounts existen:
-- SELECT u.email, a.account_type, a.id 
-- FROM accounts a 
-- JOIN users u ON u.id = a.user_id 
-- WHERE u.email LIKE 'platform%' 
-- ORDER BY a.account_type;
--
-- Para ver triggers activos:
-- SELECT tgname, tgrelid::regclass, tgfoid::regproc 
-- FROM pg_trigger 
-- WHERE tgname LIKE '%payment%';
-- ============================================================================
