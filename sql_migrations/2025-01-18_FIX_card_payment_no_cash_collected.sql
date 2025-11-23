-- ============================================================================
-- FIX: Sistema de transacciones para pagos con TARJETA sin CASH_COLLECTED
-- ============================================================================
-- Problema: Para pagos con tarjeta, se está registrando CASH_COLLECTED negativo
--           en platform_payables, lo cual es conceptualmente incorrecto.
--
-- Realidad: Cuando se paga con tarjeta, MercadoPago ya depositó el dinero 
--           completo en la cuenta de la plataforma. NO hay "efectivo cobrado".
--
-- Solución: Para tarjeta, registrar las DEUDAS de la plataforma hacia 
--           restaurant y delivery_agent como transacciones negativas directas,
--           SIN usar CASH_COLLECTED.
--
-- Balance 0 se mantiene:
--   Restaurant: +RESTAURANT_PAYABLE
--   Delivery:   +DELIVERY_EARNING
--   Platform:   +PLATFORM_COMMISSION + PLATFORM_DELIVERY_MARGIN
--               -RESTAURANT_PAYABLE (debe pagar)
--               -DELIVERY_EARNING (debe pagar)
--   = 0
-- ============================================================================

BEGIN;

-- ============================================================================
-- PASO 1: Crear nueva versión del trigger (v4) con flujo correcto
-- ============================================================================

CREATE OR REPLACE FUNCTION public.process_order_delivery_v4()
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

  v_settlement_id uuid;
  v_short_order text := '';
BEGIN
  IF NEW.status = 'delivered' AND (OLD.status IS DISTINCT FROM 'delivered') THEN
    v_short_order := LEFT(NEW.id::text, 8);

    -- Restaurant config
    SELECT COALESCE(r.commission_bps, 1500), r.user_id
    INTO v_commission_bps, v_restaurant_user_id
    FROM public.restaurants r
    WHERE r.id = NEW.restaurant_id;

    IF v_restaurant_user_id IS NULL THEN
      RAISE WARNING '[delivery_v4] Restaurant not found for order %', NEW.id;
      RETURN NEW;
    END IF;

    -- Clamp and compute amounts
    v_commission_bps := GREATEST(0, LEAST(3000, v_commission_bps));
    v_commission_rate := v_commission_bps / 10000.0;
    v_platform_commission := ROUND(COALESCE(NEW.subtotal, NEW.total_amount - COALESCE(NEW.delivery_fee, 0)) * v_commission_rate, 2);
    v_restaurant_net := ROUND(COALESCE(NEW.subtotal, NEW.total_amount - COALESCE(NEW.delivery_fee, 0)) - v_platform_commission, 2);
    v_delivery_earning := ROUND(COALESCE(NEW.delivery_fee, 0) * 0.85, 2);
    v_platform_delivery_margin := ROUND(COALESCE(NEW.delivery_fee, 0) - v_delivery_earning, 2);

    v_payment_method := COALESCE(NEW.payment_method, 'cash');

    -- Resolve accounts
    SELECT a.id INTO v_restaurant_account_id
    FROM public.accounts a
    WHERE a.user_id = v_restaurant_user_id AND a.account_type = 'restaurant'
    ORDER BY a.created_at DESC
    LIMIT 1;

    IF NEW.delivery_agent_id IS NOT NULL THEN
      SELECT a.id INTO v_delivery_account_id
      FROM public.accounts a
      WHERE a.user_id = NEW.delivery_agent_id AND a.account_type = 'delivery_agent'
      ORDER BY a.created_at DESC
      LIMIT 1;
    END IF;

    SELECT a.id INTO v_platform_revenue_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_revenue'
    ORDER BY a.created_at DESC
    LIMIT 1;

    SELECT a.id INTO v_platform_payables_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_payables'
    ORDER BY a.created_at DESC
    LIMIT 1;

    IF v_restaurant_account_id IS NULL OR v_platform_revenue_account_id IS NULL OR v_platform_payables_account_id IS NULL THEN
      RAISE WARNING '[delivery_v4] Missing core accounts for order %', NEW.id;
      RETURN NEW;
    END IF;

    -- ========================================================================
    -- TRANSACCIONES SEGÚN MÉTODO DE PAGO
    -- ========================================================================

    IF v_payment_method = 'card' THEN
      -- ====================================================================
      -- PAGO CON TARJETA: La plataforma YA recibió el dinero de MercadoPago
      -- ====================================================================
      
      -- 1. Ingreso de la plataforma (comisiones)
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_COMMISSION',
        v_platform_commission,
        NEW.id,
        'Comisión plataforma ' || v_commission_bps || 'bps orden #' || v_short_order,
        jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'card')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_DELIVERY_MARGIN',
        v_platform_delivery_margin,
        NEW.id,
        'Margen plataforma delivery 15% orden #' || v_short_order,
        jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.15, 'payment_method', 'card')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      -- 2. Deuda de la plataforma hacia el restaurante (negativo en platform_payables)
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_payables_account_id,
        'RESTAURANT_PAYABLE',
        -v_restaurant_net,
        NEW.id,
        'Deuda con restaurante orden #' || v_short_order,
        jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'card')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      -- 3. Crédito al restaurante (positivo en restaurant)
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_restaurant_account_id,
        'RESTAURANT_PAYABLE',
        v_restaurant_net,
        NEW.id,
        'Pago neto restaurante orden #' || v_short_order,
        jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'card')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      -- 4. Deuda de la plataforma hacia el repartidor (negativo en platform_payables)
      IF v_delivery_account_id IS NOT NULL AND COALESCE(NEW.delivery_fee, 0) > 0 THEN
        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_platform_payables_account_id,
          'DELIVERY_EARNING',
          -v_delivery_earning,
          NEW.id,
          'Deuda con repartidor orden #' || v_short_order,
          jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.85, 'payment_method', 'card')
        )
        ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

        -- 5. Crédito al repartidor (positivo en delivery_agent)
        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_delivery_account_id,
          'DELIVERY_EARNING',
          v_delivery_earning,
          NEW.id,
          'Ganancia delivery 85% orden #' || v_short_order,
          jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.85, 'payment_method', 'card')
        )
        ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
      END IF;

      -- Crear settlements pendientes (platform debe pagar)
      INSERT INTO public.settlements (payer_account_id, receiver_account_id, amount, status, confirmation_code, initiated_at, notes)
      VALUES (v_platform_payables_account_id, v_restaurant_account_id, v_restaurant_net, 'pending', LPAD(FLOOR(RANDOM()*10000)::text, 4, '0'), now(), 'Orden #' || v_short_order || ' (card → restaurant)')
      RETURNING id INTO v_settlement_id;

      IF v_delivery_account_id IS NOT NULL AND v_delivery_earning > 0 THEN
        INSERT INTO public.settlements (payer_account_id, receiver_account_id, amount, status, confirmation_code, initiated_at, notes)
        VALUES (v_platform_payables_account_id, v_delivery_account_id, v_delivery_earning, 'pending', LPAD(FLOOR(RANDOM()*10000)::text, 4, '0'), now(), 'Orden #' || v_short_order || ' (card → delivery)')
        RETURNING id INTO v_settlement_id;
      END IF;

    ELSE
      -- ====================================================================
      -- PAGO EN EFECTIVO: El repartidor cobra y debe entregar parte
      -- ====================================================================

      -- 1. Ingreso de la plataforma (comisiones)
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_COMMISSION',
        v_platform_commission,
        NEW.id,
        'Comisión plataforma ' || v_commission_bps || 'bps orden #' || v_short_order,
        jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'cash')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_DELIVERY_MARGIN',
        v_platform_delivery_margin,
        NEW.id,
        'Margen plataforma delivery 15% orden #' || v_short_order,
        jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.15, 'payment_method', 'cash')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      -- 2. Crédito al restaurante
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_restaurant_account_id,
        'RESTAURANT_PAYABLE',
        v_restaurant_net,
        NEW.id,
        'Pago neto restaurante orden #' || v_short_order,
        jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'cash')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      -- 3. Crédito al repartidor
      IF v_delivery_account_id IS NOT NULL AND COALESCE(NEW.delivery_fee, 0) > 0 THEN
        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_delivery_account_id,
          'DELIVERY_EARNING',
          v_delivery_earning,
          NEW.id,
          'Ganancia delivery 85% orden #' || v_short_order,
          jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.85, 'payment_method', 'cash')
        )
        ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

        -- 4. CASH_COLLECTED: Efectivo recolectado por el repartidor (negativo)
        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_delivery_account_id,
          'CASH_COLLECTED',
          -NEW.total_amount,
          NEW.id,
          'Efectivo recolectado orden #' || v_short_order,
          jsonb_build_object('total', NEW.total_amount, 'payment_method', 'cash', 'collected_by_delivery', true)
        )
        ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
      END IF;

      -- Crear settlement pendiente (delivery debe entregar a platform)
      IF v_delivery_account_id IS NOT NULL THEN
        INSERT INTO public.settlements (payer_account_id, receiver_account_id, amount, status, confirmation_code, initiated_at, initiated_by, notes)
        VALUES (v_delivery_account_id, v_platform_payables_account_id, (NEW.total_amount - v_delivery_earning), 'pending', LPAD(FLOOR(RANDOM()*10000)::text, 4, '0'), now(), NEW.delivery_agent_id, 'Orden #' || v_short_order || ' (cash → platform)')
        RETURNING id INTO v_settlement_id;
      END IF;

    END IF;

    RAISE NOTICE '✅ [delivery_v4] order % processed (method %, net_rest %, deliv %)', NEW.id, v_payment_method, v_restaurant_net, v_delivery_earning;
  END IF;

  RETURN NEW;
END;
$$;

-- Reemplazar trigger
DROP TRIGGER IF EXISTS trg_on_order_delivered_process_v3 ON public.orders;
DROP TRIGGER IF EXISTS trg_on_order_delivered_process_v4 ON public.orders;

CREATE TRIGGER trg_on_order_delivered_process_v4
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'delivered')
EXECUTE FUNCTION public.process_order_delivery_v4();

-- ============================================================================
-- PASO 2: Limpiar transacciones incorrectas de órdenes con TARJETA
-- ============================================================================

-- Eliminar CASH_COLLECTED de órdenes con tarjeta
DELETE FROM public.account_transactions
WHERE type = 'CASH_COLLECTED'
  AND order_id IN (
    SELECT id FROM public.orders WHERE payment_method = 'card' AND status = 'delivered'
  );

-- ============================================================================
-- PASO 3: Recrear transacciones para órdenes con tarjeta ya entregadas
-- ============================================================================

DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN 
    SELECT o.id
    FROM public.orders o
    WHERE o.status = 'delivered'
      AND o.payment_method = 'card'
      -- Solo recrear si NO tiene la estructura correcta
      AND NOT EXISTS (
        SELECT 1 FROM public.account_transactions at
        WHERE at.order_id = o.id 
          AND at.type = 'RESTAURANT_PAYABLE'
          AND at.account_id IN (SELECT id FROM accounts WHERE account_type = 'platform_payables')
          AND at.amount < 0
      )
  LOOP
    -- Eliminar transacciones existentes
    DELETE FROM public.account_transactions WHERE order_id = rec.id;
    
    -- Temporalmente cambiar status para re-disparar el trigger
    UPDATE public.orders 
    SET status = 'preparing', updated_at = now()
    WHERE id = rec.id;
    
    -- Volver a 'delivered' - esto dispara process_order_delivery_v4()
    UPDATE public.orders 
    SET status = 'delivered', updated_at = now()
    WHERE id = rec.id;
    
    RAISE NOTICE '✅ Recreadas transacciones para orden % (tarjeta)', LEFT(rec.id::text, 8);
  END LOOP;
END $$;

-- ============================================================================
-- PASO 4: Validar balance = 0
-- ============================================================================

DO $$
DECLARE
  v_global_balance numeric;
  v_unbalanced_count integer;
BEGIN
  -- Balance global
  SELECT COALESCE(SUM(amount), 0) INTO v_global_balance
  FROM public.account_transactions;
  
  -- Órdenes desbalanceadas
  SELECT COUNT(*) INTO v_unbalanced_count
  FROM (
    SELECT order_id, SUM(amount) as balance
    FROM public.account_transactions
    WHERE order_id IS NOT NULL
    GROUP BY order_id
    HAVING ABS(SUM(amount)) > 0.01
  ) x;
  
  RAISE NOTICE '========================================';
  RAISE NOTICE 'VALIDACIÓN FINAL';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Balance global: $%', ROUND(v_global_balance, 2);
  RAISE NOTICE 'Órdenes con desbalance: %', v_unbalanced_count;
  
  IF ABS(v_global_balance) < 0.01 AND v_unbalanced_count = 0 THEN
    RAISE NOTICE '✅ Sistema en BALANCE 0 perfecto';
  ELSE
    RAISE WARNING '❌ Sistema AÚN tiene desbalance';
  END IF;
  RAISE NOTICE '========================================';
END $$;

COMMIT;
