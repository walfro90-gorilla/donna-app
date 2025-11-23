-- =====================================================================
-- 🔥 SOLUCIÓN DEFINITIVA: Constraint + Trigger V3 FINAL
-- =====================================================================
-- PROBLEMA:
--   - El constraint uq_account_txn_order_account_type puede existir como:
--     a) CONSTRAINT único
--     b) INDEX único
--   - La verificación anterior solo chequeaba constraints, no indexes
--
-- SOLUCIÓN:
--   1. Eliminar CUALQUIER constraint/index previo con ese nombre
--   2. Recrear el constraint desde cero
--   3. Crear función + trigger v3 limpio
-- =====================================================================

-- ==========================================
-- PASO 1: LIMPIAR TRIGGERS/FUNCIONES LEGACY
-- ==========================================
DO $$
BEGIN
  RAISE NOTICE '🗑️  Limpiando triggers y funciones legacy...';
END $$;

DROP TRIGGER IF EXISTS trigger_process_order_payment_final ON public.orders CASCADE;
DROP TRIGGER IF EXISTS trigger_process_order_payment_v2_canonical ON public.orders CASCADE;
DROP TRIGGER IF EXISTS trigger_process_order_delivery_v3 ON public.orders CASCADE;
DROP TRIGGER IF EXISTS trg_process_payments_on_delivery ON public.orders CASCADE;
DROP TRIGGER IF EXISTS trigger_process_payment_on_delivery ON public.orders CASCADE;
DROP TRIGGER IF EXISTS trigger_order_financial_completion ON public.orders CASCADE;
DROP TRIGGER IF EXISTS trigger_process_order_payment ON public.orders CASCADE;
DROP TRIGGER IF EXISTS trg_order_status_update ON public.orders CASCADE;

DROP FUNCTION IF EXISTS public.process_order_payment_final() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment_v2() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_delivery_v3() CASCADE;
DROP FUNCTION IF EXISTS public.process_payments_on_delivery() CASCADE;
DROP FUNCTION IF EXISTS public.process_payment_on_delivery() CASCADE;
DROP FUNCTION IF EXISTS public.handle_order_financial_completion() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment() CASCADE;

DO $$
BEGIN
  RAISE NOTICE '✅ Cleanup de triggers/funciones completado';
END $$;

-- ==========================================
-- PASO 2: ELIMINAR CONSTRAINT/INDEX PREVIO
-- ==========================================
DO $$
DECLARE
  v_constraint_exists boolean;
  v_index_exists boolean;
BEGIN
  -- Verificar si existe como CONSTRAINT
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'uq_account_txn_order_account_type'
  ) INTO v_constraint_exists;
  
  -- Verificar si existe como INDEX
  SELECT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE indexname = 'uq_account_txn_order_account_type'
  ) INTO v_index_exists;
  
  RAISE NOTICE '🔍 Estado actual:';
  RAISE NOTICE '  - Constraint existe: %', v_constraint_exists;
  RAISE NOTICE '  - Index existe: %', v_index_exists;
  
  -- Eliminar constraint si existe
  IF v_constraint_exists THEN
    EXECUTE 'ALTER TABLE public.account_transactions DROP CONSTRAINT IF EXISTS uq_account_txn_order_account_type';
    RAISE NOTICE '🗑️  Constraint eliminado';
  END IF;
  
  -- Eliminar index si existe
  IF v_index_exists THEN
    EXECUTE 'DROP INDEX IF EXISTS public.uq_account_txn_order_account_type';
    RAISE NOTICE '🗑️  Index eliminado';
  END IF;
  
  RAISE NOTICE '✅ Limpieza de constraint/index completada';
END $$;

-- ==========================================
-- PASO 3: CREAR CONSTRAINT ÚNICO FRESCO
-- ==========================================
DO $$
BEGIN
  ALTER TABLE public.account_transactions
    ADD CONSTRAINT uq_account_txn_order_account_type
    UNIQUE (order_id, account_id, type);
  
  RAISE NOTICE '✅ Constraint único creado: uq_account_txn_order_account_type';
END $$;

-- ==========================================
-- PASO 4: VERIFICAR TIPOS PERMITIDOS
-- ==========================================
DO $$
BEGIN
  -- Eliminar constraint de tipos si existe
  ALTER TABLE public.account_transactions DROP CONSTRAINT IF EXISTS account_transactions_type_check;
  
  -- Recrear con TODOS los tipos
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
      'CLIENT_DEBT'
    ));
  
  RAISE NOTICE '✅ Constraint de tipos actualizado';
END $$;

-- ==========================================
-- PASO 5: CREAR FUNCIÓN IDEMPOTENTE V3
-- ==========================================
CREATE OR REPLACE FUNCTION public.process_order_delivery_v3()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_commission_bps integer;
  v_commission_rate numeric(10,4);
  v_platform_commission numeric(10,2);
  v_restaurant_net numeric(10,2);
  v_delivery_earning numeric(10,2);
  v_platform_delivery_margin numeric(10,2);
  
  v_restaurant_account_id uuid;
  v_delivery_account_id uuid;
  v_platform_revenue_account_id uuid;
  v_platform_payables_account_id uuid;
  
  v_payment_method text;
  v_restaurant_user_id uuid;
BEGIN
  IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status IS DISTINCT FROM 'delivered') THEN
    
    RAISE NOTICE '🔄 Procesando orden % como delivered', NEW.id;
    
    -- Obtener datos del restaurante
    SELECT 
      COALESCE(commission_bps, 1500),
      user_id
    INTO 
      v_commission_bps,
      v_restaurant_user_id
    FROM public.restaurants
    WHERE id = NEW.restaurant_id;
    
    IF v_restaurant_user_id IS NULL THEN
      RAISE WARNING '⚠️  Restaurante no encontrado: %', NEW.restaurant_id;
      RETURN NEW;
    END IF;
    
    -- Clamp commission_bps
    v_commission_bps := GREATEST(0, LEAST(3000, v_commission_bps));
    v_commission_rate := v_commission_bps / 10000.0;
    
    -- Calcular montos
    v_platform_commission := ROUND(NEW.subtotal * v_commission_rate, 2);
    v_restaurant_net := NEW.subtotal - v_platform_commission;
    v_delivery_earning := ROUND(NEW.delivery_fee * 0.85, 2);
    v_platform_delivery_margin := NEW.delivery_fee - v_delivery_earning;
    v_payment_method := COALESCE(NEW.payment_method, 'cash');
    
    -- Obtener cuentas
    SELECT id INTO v_restaurant_account_id
    FROM public.accounts
    WHERE user_id = v_restaurant_user_id AND account_type = 'restaurant'
    ORDER BY created_at DESC LIMIT 1;
    
    IF v_restaurant_account_id IS NULL THEN
      RAISE WARNING '⚠️  Cuenta de restaurante no encontrada';
      RETURN NEW;
    END IF;
    
    IF NEW.delivery_agent_id IS NOT NULL THEN
      SELECT id INTO v_delivery_account_id
      FROM public.accounts
      WHERE user_id = NEW.delivery_agent_id AND account_type = 'delivery_agent'
      ORDER BY created_at DESC LIMIT 1;
    END IF;
    
    SELECT id INTO v_platform_revenue_account_id
    FROM public.accounts
    WHERE account_type = 'platform_revenue'
    ORDER BY created_at DESC LIMIT 1;
    
    SELECT id INTO v_platform_payables_account_id
    FROM public.accounts
    WHERE account_type = 'platform_payables'
    ORDER BY created_at DESC LIMIT 1;
    
    IF v_platform_revenue_account_id IS NULL OR v_platform_payables_account_id IS NULL THEN
      RAISE WARNING '⚠️  Cuentas de plataforma no encontradas';
      RETURN NEW;
    END IF;
    
    -- Registrar en payments
    INSERT INTO public.payments (order_id, amount, status, created_at)
    VALUES (NEW.id, NEW.total_amount, 'succeeded', NOW())
    ON CONFLICT (order_id) DO NOTHING;
    
    -- Transacciones
    INSERT INTO public.account_transactions (account_id, type, amount, order_id, description, metadata)
    VALUES (
      v_platform_payables_account_id,
      'ORDER_REVENUE',
      NEW.total_amount,
      NEW.id,
      'Ingreso total orden #' || LEFT(NEW.id::text, 8),
      jsonb_build_object('commission_bps', v_commission_bps, 'subtotal', NEW.subtotal, 'delivery_fee', NEW.delivery_fee, 'payment_method', v_payment_method)
    )
    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    
    INSERT INTO public.account_transactions (account_id, type, amount, order_id, description, metadata)
    VALUES (
      v_platform_revenue_account_id,
      'PLATFORM_COMMISSION',
      v_platform_commission,
      NEW.id,
      'Comisión ' || v_commission_bps || 'bps orden #' || LEFT(NEW.id::text, 8),
      jsonb_build_object('commission_bps', v_commission_bps, 'subtotal', NEW.subtotal, 'commission', v_platform_commission, 'payment_method', v_payment_method)
    )
    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    
    INSERT INTO public.account_transactions (account_id, type, amount, order_id, description, metadata)
    VALUES (
      v_restaurant_account_id,
      'RESTAURANT_PAYABLE',
      v_restaurant_net,
      NEW.id,
      'Pago neto orden #' || LEFT(NEW.id::text, 8),
      jsonb_build_object('commission_bps', v_commission_bps, 'subtotal', NEW.subtotal, 'commission', v_platform_commission, 'net', v_restaurant_net, 'payment_method', v_payment_method)
    )
    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    
    IF v_delivery_account_id IS NOT NULL THEN
      INSERT INTO public.account_transactions (account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_delivery_account_id,
        'DELIVERY_EARNING',
        v_delivery_earning,
        NEW.id,
        'Ganancia entrega orden #' || LEFT(NEW.id::text, 8),
        jsonb_build_object('delivery_fee', NEW.delivery_fee, 'earning', v_delivery_earning, 'payment_method', v_payment_method)
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    END IF;
    
    INSERT INTO public.account_transactions (account_id, type, amount, order_id, description, metadata)
    VALUES (
      v_platform_revenue_account_id,
      'PLATFORM_DELIVERY_MARGIN',
      v_platform_delivery_margin,
      NEW.id,
      'Margen delivery orden #' || LEFT(NEW.id::text, 8),
      jsonb_build_object('delivery_fee', NEW.delivery_fee, 'margin', v_platform_delivery_margin, 'payment_method', v_payment_method)
    )
    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    
    IF v_payment_method = 'cash' AND v_delivery_account_id IS NOT NULL THEN
      INSERT INTO public.account_transactions (account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_delivery_account_id,
        'CASH_COLLECTED',
        -NEW.total_amount,
        NEW.id,
        'Efectivo recolectado orden #' || LEFT(NEW.id::text, 8),
        jsonb_build_object('total', NEW.total_amount, 'payment_method', v_payment_method)
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    END IF;
    
    RAISE NOTICE '✅ Orden % procesada: commission=%bps net=% delivery=%', 
      NEW.id, v_commission_bps, v_restaurant_net, v_delivery_earning;
  END IF;
  
  RETURN NEW;
END;
$$;

-- ==========================================
-- PASO 6: CREAR TRIGGER V3
-- ==========================================
CREATE TRIGGER trigger_process_order_delivery_v3
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status IS DISTINCT FROM 'delivered'))
  EXECUTE FUNCTION public.process_order_delivery_v3();

-- ==========================================
-- PASO 7: VERIFICACIÓN FINAL
-- ==========================================
DO $$
DECLARE
  v_trigger_count integer;
  v_constraint_exists boolean;
  v_function_exists boolean;
BEGIN
  SELECT COUNT(*) INTO v_trigger_count
  FROM information_schema.triggers
  WHERE event_object_schema = 'public'
    AND event_object_table = 'orders'
    AND (trigger_name LIKE '%payment%' OR trigger_name LIKE '%delivery%');
  
  SELECT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_account_txn_order_account_type'
  ) INTO v_constraint_exists;
  
  SELECT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'process_order_delivery_v3'
  ) INTO v_function_exists;
  
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ MIGRACIÓN V3 COMPLETADA EXITOSAMENTE';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🎯 Trigger: trigger_process_order_delivery_v3';
  RAISE NOTICE '📦 Función: process_order_delivery_v3() (existe: %)', v_function_exists;
  RAISE NOTICE '🔒 Constraint: uq_account_txn_order_account_type (existe: %)', v_constraint_exists;
  RAISE NOTICE '📊 Triggers activos payment/delivery: %', v_trigger_count;
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ Sistema listo para procesar órdenes delivered';
  RAISE NOTICE '========================================';
END $$;
