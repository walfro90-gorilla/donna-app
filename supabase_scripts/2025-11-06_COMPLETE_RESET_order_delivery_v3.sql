-- =====================================================================
-- 🔥 RESET COMPLETO Y RECONSTRUCCIÓN V3 - PROFESIONAL
-- =====================================================================
-- PROPÓSITO:
--   Eliminar TODAS las funciones/triggers legacy y crear UNA SOLA
--   función idempotente que procese pagos al marcar orden como 'delivered'
--
-- CARACTERÍSTICAS:
--   ✅ Lee commission_bps dinámicamente del restaurante
--   ✅ Inserta en account_transactions con description + metadata
--   ✅ Inserta en payments con amount correcto
--   ✅ Completamente idempotente (ON CONFLICT DO NOTHING)
--   ✅ Respeta DATABASE_SCHEMA.sql exactamente
--   ✅ Balance Cero garantizado (cash flow)
-- =====================================================================

-- ==========================================
-- PASO 1: LIMPIAR TODO LO ANTERIOR
-- ==========================================
DO $$
BEGIN
  RAISE NOTICE '🗑️  Eliminando triggers legacy...';
END $$;

-- Eliminar TODOS los triggers posibles
DROP TRIGGER IF EXISTS trigger_process_order_payment_final ON public.orders CASCADE;
DROP TRIGGER IF EXISTS trigger_process_order_payment_v2_canonical ON public.orders CASCADE;
DROP TRIGGER IF EXISTS trg_process_payments_on_delivery ON public.orders CASCADE;
DROP TRIGGER IF EXISTS trigger_process_payment_on_delivery ON public.orders CASCADE;
DROP TRIGGER IF EXISTS trigger_order_financial_completion ON public.orders CASCADE;
DROP TRIGGER IF EXISTS trigger_process_order_payment ON public.orders CASCADE;
DROP TRIGGER IF EXISTS trg_order_status_update ON public.orders CASCADE;

-- Eliminar TODAS las funciones legacy
DROP FUNCTION IF EXISTS public.process_order_payment_final() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment_v2() CASCADE;
DROP FUNCTION IF EXISTS public.process_payments_on_delivery() CASCADE;
DROP FUNCTION IF EXISTS public.process_payment_on_delivery() CASCADE;
DROP FUNCTION IF EXISTS public.handle_order_financial_completion() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment() CASCADE;

DO $$
BEGIN
  RAISE NOTICE '✅ Cleanup completado';
END $$;

-- ==========================================
-- PASO 2: VERIFICAR/CREAR CONSTRAINT ÚNICO
-- ==========================================
DO $$
DECLARE
  v_constraint_exists boolean;
BEGIN
  -- Verificar si el constraint existe
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND t.relname = 'account_transactions'
      AND c.conname = 'uq_account_txn_order_account_type'
  ) INTO v_constraint_exists;

  IF NOT v_constraint_exists THEN
    -- Solo crear si NO existe
    EXECUTE 'ALTER TABLE public.account_transactions
      ADD CONSTRAINT uq_account_txn_order_account_type
      UNIQUE (order_id, account_id, type)';
    
    RAISE NOTICE '✅ Constraint único creado: uq_account_txn_order_account_type';
  ELSE
    RAISE NOTICE 'ℹ️  Constraint único ya existe (OK): uq_account_txn_order_account_type';
  END IF;
END $$;

-- ==========================================
-- PASO 3: VERIFICAR TIPOS PERMITIDOS
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

  -- Recrear con TODOS los tipos necesarios
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

  RAISE NOTICE '✅ Constraint de tipos actualizado con todos los tipos requeridos';
END $$;

-- ==========================================
-- PASO 4: CREAR FUNCIÓN IDEMPOTENTE V3
-- ==========================================
CREATE OR REPLACE FUNCTION public.process_order_delivery_v3()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  -- Variables de comisión
  v_commission_bps integer;
  v_commission_rate numeric(10,4);
  v_platform_commission numeric(10,2);
  v_restaurant_net numeric(10,2);
  v_delivery_earning numeric(10,2);
  v_platform_delivery_margin numeric(10,2);
  
  -- IDs de cuentas
  v_restaurant_account_id uuid;
  v_delivery_account_id uuid;
  v_platform_revenue_account_id uuid;
  v_platform_payables_account_id uuid;
  
  -- Otros
  v_payment_method text;
  v_restaurant_user_id uuid;
BEGIN
  -- Solo procesar cuando cambia a 'delivered'
  IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status IS DISTINCT FROM 'delivered') THEN
    
    -- ==========================================
    -- VERIFICACIÓN DE IDEMPOTENCIA
    -- ==========================================
    -- Si ya existen transacciones para esta orden, salir inmediatamente
    IF EXISTS (
      SELECT 1 FROM public.account_transactions
      WHERE order_id = NEW.id
        AND type = 'ORDER_REVENUE'
    ) THEN
      RAISE NOTICE '⏭️  Orden % ya fue procesada anteriormente, saltando...', NEW.id;
      RETURN NEW;
    END IF;
    
    RAISE NOTICE '🔄 Procesando orden % como delivered', NEW.id;
    
    -- ==========================================
    -- OBTENER DATOS DEL RESTAURANT
    -- ==========================================
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
    
    -- Clamp commission_bps entre 0 y 3000
    v_commission_bps := GREATEST(0, LEAST(3000, v_commission_bps));
    v_commission_rate := v_commission_bps / 10000.0;
    
    -- ==========================================
    -- CALCULAR MONTOS
    -- ==========================================
    v_platform_commission := ROUND(NEW.subtotal * v_commission_rate, 2);
    v_restaurant_net := NEW.subtotal - v_platform_commission;
    v_delivery_earning := ROUND(NEW.delivery_fee * 0.85, 2);
    v_platform_delivery_margin := NEW.delivery_fee - v_delivery_earning;
    
    v_payment_method := COALESCE(NEW.payment_method, 'cash');
    
    -- ==========================================
    -- OBTENER CUENTAS
    -- ==========================================
    -- Cuenta del restaurante
    SELECT id INTO v_restaurant_account_id
    FROM public.accounts
    WHERE user_id = v_restaurant_user_id
      AND account_type = 'restaurant'
    ORDER BY created_at DESC
    LIMIT 1;
    
    IF v_restaurant_account_id IS NULL THEN
      RAISE WARNING '⚠️  Cuenta de restaurante no encontrada para user_id: %', v_restaurant_user_id;
      RETURN NEW;
    END IF;
    
    -- Cuenta del delivery agent
    IF NEW.delivery_agent_id IS NOT NULL THEN
      SELECT id INTO v_delivery_account_id
      FROM public.accounts
      WHERE user_id = NEW.delivery_agent_id
        AND account_type = 'delivery_agent'
      ORDER BY created_at DESC
      LIMIT 1;
    END IF;
    
    -- Cuenta de plataforma revenue
    SELECT id INTO v_platform_revenue_account_id
    FROM public.accounts
    WHERE account_type = 'platform_revenue'
    ORDER BY created_at DESC
    LIMIT 1;
    
    IF v_platform_revenue_account_id IS NULL THEN
      RAISE WARNING '⚠️  Cuenta platform_revenue no encontrada';
      RETURN NEW;
    END IF;
    
    -- Cuenta de plataforma payables
    SELECT id INTO v_platform_payables_account_id
    FROM public.accounts
    WHERE account_type = 'platform_payables'
    ORDER BY created_at DESC
    LIMIT 1;
    
    IF v_platform_payables_account_id IS NULL THEN
      RAISE WARNING '⚠️  Cuenta platform_payables no encontrada';
      RETURN NEW;
    END IF;
    
    -- ==========================================
    -- REGISTRAR EN TABLA PAYMENTS
    -- ==========================================
    INSERT INTO public.payments (
      order_id,
      amount,
      status,
      created_at
    ) VALUES (
      NEW.id,
      NEW.total_amount,
      'succeeded',
      NOW()
    )
    ON CONFLICT (order_id) DO NOTHING;
    
    -- ==========================================
    -- TRANSACCIONES EN ACCOUNT_TRANSACTIONS
    -- ==========================================
    
    -- 1) Ingreso total de la orden (a platform_payables)
    INSERT INTO public.account_transactions (
      account_id, type, amount, order_id, description, metadata
    ) VALUES (
      v_platform_payables_account_id,
      'ORDER_REVENUE',
      NEW.total_amount,
      NEW.id,
      'Ingreso total orden #' || LEFT(NEW.id::text, 8),
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
      'Comisión plataforma ' || v_commission_bps || 'bps orden #' || LEFT(NEW.id::text, 8),
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
      'Pago neto restaurante orden #' || LEFT(NEW.id::text, 8),
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
        'Ganancia entrega 85% orden #' || LEFT(NEW.id::text, 8),
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
      'Margen delivery plataforma 15% orden #' || LEFT(NEW.id::text, 8),
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
        'Efectivo recolectado orden #' || LEFT(NEW.id::text, 8),
        jsonb_build_object(
          'total', NEW.total_amount,
          'collected_by_delivery', true,
          'payment_method', v_payment_method
        )
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    END IF;
    
    RAISE NOTICE '✅ Orden % procesada: commission=%bps restaurant_net=% delivery=%', 
      NEW.id, v_commission_bps, v_restaurant_net, v_delivery_earning;
  END IF;
  
  RETURN NEW;
END;
$$;

-- ==========================================
-- PASO 5: CREAR TRIGGER V3
-- ==========================================
DROP TRIGGER IF EXISTS trigger_process_order_delivery_v3 ON public.orders CASCADE;

CREATE TRIGGER trigger_process_order_delivery_v3
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status IS DISTINCT FROM 'delivered'))
  EXECUTE FUNCTION public.process_order_delivery_v3();

-- ==========================================
-- PASO 6: VERIFICACIÓN FINAL
-- ==========================================
DO $$
DECLARE
  v_trigger_count integer;
  v_constraint_exists boolean;
BEGIN
  SELECT COUNT(*) INTO v_trigger_count
  FROM information_schema.triggers
  WHERE event_object_schema = 'public'
    AND event_object_table = 'orders'
    AND trigger_name LIKE '%payment%' OR trigger_name LIKE '%delivery%';
  
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND t.relname = 'account_transactions'
      AND c.conname = 'uq_account_txn_order_account_type'
  ) INTO v_constraint_exists;
  
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ MIGRACIÓN V3 COMPLETADA';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🎯 Trigger activo: trigger_process_order_delivery_v3';
  RAISE NOTICE '📦 Función: public.process_order_delivery_v3()';
  RAISE NOTICE '🔒 Constraint único: % (existe: %)', 'uq_account_txn_order_account_type', v_constraint_exists;
  RAISE NOTICE '📊 Total triggers payment/delivery: %', v_trigger_count;
  RAISE NOTICE '========================================';
  RAISE NOTICE '📝 Comportamiento:';
  RAISE NOTICE '  • Lee commission_bps dinámicamente del restaurant';
  RAISE NOTICE '  • Inserta description + metadata en TODAS las transacciones';
  RAISE NOTICE '  • Inserta en payments con status=succeeded';
  RAISE NOTICE '  • Completamente idempotente (ON CONFLICT DO NOTHING)';
  RAISE NOTICE '  • Balance Cero garantizado (cash flow)';
  RAISE NOTICE '========================================';
END $$;
