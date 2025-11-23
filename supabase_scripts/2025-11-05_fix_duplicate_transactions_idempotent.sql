-- =====================================================================
-- FIX: Transacciones duplicadas al marcar orden como 'delivered'
-- =====================================================================
-- PROBLEMA:
-- - Error: "duplicate key value violates unique constraint uq_account_txn_order_account_type"
-- - El trigger se ejecuta múltiples veces causando duplicados
-- 
-- SOLUCIÓN:
-- 1. Crear constraint único si no existe
-- 2. Corregir tipo RESTAURANT_EARNING → RESTAURANT_PAYABLE
-- 3. Hacer función completamente idempotente con ON CONFLICT
-- =====================================================================

-- ==========================================
-- 1) CREAR CONSTRAINT ÚNICO IDEMPOTENTE
-- ==========================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND t.relname = 'account_transactions'
      AND c.conname = 'uq_account_txn_order_account_type'
  ) THEN
    ALTER TABLE public.account_transactions
      ADD CONSTRAINT uq_account_txn_order_account_type
      UNIQUE (order_id, account_id, type);
    
    RAISE NOTICE '✅ Constraint único creado: uq_account_txn_order_account_type';
  ELSE
    RAISE NOTICE 'ℹ️  Constraint único ya existe: uq_account_txn_order_account_type';
  END IF;
END $$;

-- ==========================================
-- 2) AGREGAR TIPO RESTAURANT_EARNING SI FALTA
-- ==========================================
DO $$
BEGIN
  -- Eliminar constraint existente
  IF EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND t.relname = 'account_transactions'
      AND c.conname = 'account_transactions_type_check'
  ) THEN
    ALTER TABLE public.account_transactions DROP CONSTRAINT account_transactions_type_check;
  END IF;

  -- Recrear con TODOS los tipos (incluido RESTAURANT_EARNING para compatibilidad)
  ALTER TABLE public.account_transactions
    ADD CONSTRAINT account_transactions_type_check
    CHECK (type IN (
      'ORDER_REVENUE',
      'PLATFORM_COMMISSION',
      'DELIVERY_EARNING',
      'CASH_COLLECTED',
      'SETTLEMENT_PAYMENT',
      'SETTLEMENT_RECEPTION',
      'RESTAURANT_PAYABLE',
      'DELIVERY_PAYABLE',
      'PLATFORM_DELIVERY_MARGIN',
      'CLIENT_DEBT',
      'RESTAURANT_EARNING'
    ));

  RAISE NOTICE '✅ Constraint de tipos actualizado';
END $$;

-- ==========================================
-- 3) ELIMINAR FUNCIÓN Y TRIGGER EXISTENTES
-- ==========================================
DROP TRIGGER IF EXISTS trigger_process_order_payment_v2_canonical ON public.orders;
DROP FUNCTION IF EXISTS public.process_order_payment_v2() CASCADE;

-- ==========================================
-- 4) CREAR FUNCIÓN IDEMPOTENTE COMPLETA
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
    -- Solo procesar cuando cambia a 'delivered'
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
        
        -- Método de pago (usar el del pedido, no de payments)
        v_payment_method := COALESCE(NEW.payment_method, 'cash');
        
        -- ==========================================
        -- INSERTAR TRANSACCIONES (IDEMPOTENTE)
        -- ==========================================
        
        -- 1) Ingreso total de la orden (a platform_payables)
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata
        ) VALUES (
            v_platform_payables_account_id,
            'ORDER_REVENUE',
            NEW.total_amount,
            NEW.id,
            'Ingreso total orden #' || NEW.id,
            jsonb_build_object(
                'commission_bps', v_commission_bps,
                'commission_rate', v_commission_rate,
                'subtotal', NEW.subtotal,
                'delivery_fee', NEW.delivery_fee,
                'payment_method', v_payment_method
            )
        )
        ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
        
        -- 2) Comisión de plataforma (ingreso a platform_revenue)
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata
        ) VALUES (
            v_platform_revenue_account_id,
            'PLATFORM_COMMISSION',
            v_platform_commission,
            NEW.id,
            'Comisión plataforma (' || v_commission_bps || ' bps) - Orden #' || NEW.id,
            jsonb_build_object(
                'commission_bps', v_commission_bps,
                'commission_rate', v_commission_rate,
                'subtotal', NEW.subtotal,
                'calculated_commission', v_platform_commission,
                'payment_method', v_payment_method
            )
        )
        ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
        
        -- 3) Pago al restaurante (neto después de comisión)
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata
        ) VALUES (
            v_restaurant_account_id,
            'RESTAURANT_PAYABLE',
            v_restaurant_net,
            NEW.id,
            'Pago neto restaurante orden #' || NEW.id,
            jsonb_build_object(
                'commission_bps', v_commission_bps,
                'commission_rate', v_commission_rate,
                'subtotal', NEW.subtotal,
                'commission_deducted', v_platform_commission,
                'net_amount', v_restaurant_net,
                'payment_method', v_payment_method
            )
        )
        ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
        
        -- 4) Ganancia del delivery (85% del delivery_fee)
        IF v_delivery_account_id IS NOT NULL THEN
            INSERT INTO public.account_transactions (
                account_id, type, amount, order_id, description, metadata
            ) VALUES (
                v_delivery_account_id,
                'DELIVERY_EARNING',
                v_delivery_earning,
                NEW.id,
                'Ganancia entrega (85%) - Orden #' || NEW.id,
                jsonb_build_object(
                    'delivery_fee', NEW.delivery_fee,
                    'delivery_percentage', 0.85,
                    'calculated_earning', v_delivery_earning,
                    'payment_method', v_payment_method
                )
            )
            ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
        END IF;
        
        -- 5) Margen de plataforma por delivery (15%)
        INSERT INTO public.account_transactions (
            account_id, type, amount, order_id, description, metadata
        ) VALUES (
            v_platform_revenue_account_id,
            'PLATFORM_DELIVERY_MARGIN',
            v_platform_delivery_margin,
            NEW.id,
            'Margen delivery plataforma (15%) - Orden #' || NEW.id,
            jsonb_build_object(
                'delivery_fee', NEW.delivery_fee,
                'platform_percentage', 0.15,
                'calculated_margin', v_platform_delivery_margin,
                'payment_method', v_payment_method
            )
        )
        ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
        
        -- 6) Efectivo recolectado (si es pago en efectivo)
        IF v_payment_method = 'cash' AND v_delivery_account_id IS NOT NULL THEN
            INSERT INTO public.account_transactions (
                account_id, type, amount, order_id, description, metadata
            ) VALUES (
                v_delivery_account_id,
                'CASH_COLLECTED',
                -NEW.total_amount,
                NEW.id,
                'Efectivo recolectado - Orden #' || NEW.id,
                jsonb_build_object(
                    'total', NEW.total_amount,
                    'collected_by_delivery', true,
                    'payment_method', v_payment_method
                )
            )
            ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
        END IF;
        
        RAISE NOTICE '✅ Transacciones procesadas (idempotente) commission_bps=%', v_commission_bps;
    END IF;
    
    RETURN NEW;
END;
$$;

-- ==========================================
-- 5) CREAR TRIGGER CANÓNICO
-- ==========================================
CREATE TRIGGER trigger_process_order_payment_v2_canonical
    AFTER UPDATE ON public.orders
    FOR EACH ROW
    WHEN (NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status IS DISTINCT FROM 'delivered'))
    EXECUTE FUNCTION public.process_order_payment_v2();

-- ==========================================
-- 6) VERIFICACIÓN
-- ==========================================
DO $$
DECLARE
    v_trigger_count integer;
BEGIN
    SELECT COUNT(*) INTO v_trigger_count
    FROM information_schema.triggers
    WHERE event_object_table = 'orders'
    AND trigger_name LIKE '%payment%';
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ SCRIPT COMPLETADO';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Triggers activos relacionados con payment: %', v_trigger_count;
    RAISE NOTICE 'Constraint único: uq_account_txn_order_account_type';
    RAISE NOTICE 'Función: public.process_order_payment_v2()';
    RAISE NOTICE 'Trigger: trigger_process_order_payment_v2_canonical';
    RAISE NOTICE '========================================';
END $$;
