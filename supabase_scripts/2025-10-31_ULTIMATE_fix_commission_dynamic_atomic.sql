-- =====================================================================
-- SOLUCIÓN DEFINITIVA: Comisión Dinámica con commission_bps
-- =====================================================================
-- Problema: Múltiples funciones/triggers conflictivas causan que la comisión
--           siga siendo 20% fijo, sin usar restaurants.commission_bps, y sin
--           agregar description/metadata a las transacciones.
--
-- Solución: Eliminar TODA función/trigger legacy de forma exhaustiva y crear
--           UNA SOLA fuente de verdad que:
--           1. Lee restaurants.commission_bps dinámicamente (default 1500=15%)
--           2. Usa tipos correctos según DATABASE_SCHEMA.sql
--           3. Escribe description Y metadata en todas las transacciones
--           4. Mantiene Balance Cero para cash y card flows
--           5. Es idempotente (puede re-ejecutarse sin duplicar transacciones)
--
-- Garantías:
--   - Solo una función de trigger activa: process_order_payment_final()
--   - Solo un trigger activo: trigger_process_order_payment_final
--   - Usa columnas exactas del schema (order_id, no related_order_id)
--   - Respeta tipos permitidos en account_transactions.type CHECK constraint
-- =====================================================================

-- =====================================================================
-- PASO 0: ANÁLISIS Y LIMPIEZA EXHAUSTIVA
-- =====================================================================

-- Eliminar TODOS los triggers posibles relacionados con pagos en orders
DO $cleanup$
BEGIN
  -- Lista completa de nombres de triggers legacy encontrados en el código
  EXECUTE 'DROP TRIGGER IF EXISTS trigger_process_payment_on_delivery ON public.orders CASCADE';
  EXECUTE 'DROP TRIGGER IF EXISTS trigger_order_financial_completion ON public.orders CASCADE';
  EXECUTE 'DROP TRIGGER IF EXISTS trigger_process_order_payment ON public.orders CASCADE';
  EXECUTE 'DROP TRIGGER IF EXISTS trigger_process_order_payment_final ON public.orders CASCADE';
  
  RAISE NOTICE '✓ Todos los triggers legacy eliminados';
END $cleanup$;

-- Eliminar TODAS las funciones posibles relacionadas con pagos
DROP FUNCTION IF EXISTS public.process_order_payment() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment_on_delivery() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment_v2() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment_final() CASCADE;

-- Verificar columna commission_bps en restaurants y asegurar default/constraint
DO $ensure_commission$
BEGIN
  -- Agregar columna si no existe
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='restaurants' AND column_name='commission_bps'
  ) THEN
    ALTER TABLE public.restaurants ADD COLUMN commission_bps integer NOT NULL DEFAULT 1500;
    RAISE NOTICE '✓ Columna commission_bps creada con default 1500';
  ELSE
    -- Asegurar default en caso de que exista pero sin default
    ALTER TABLE public.restaurants ALTER COLUMN commission_bps SET DEFAULT 1500;
    RAISE NOTICE '✓ Columna commission_bps ya existe, default actualizado';
  END IF;

  -- Agregar constraint de validación (0..3000 basis points = 0%..30%)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname='public' AND t.relname='restaurants' AND c.conname='restaurants_commission_bps_valid_range'
  ) THEN
    ALTER TABLE public.restaurants
      ADD CONSTRAINT restaurants_commission_bps_valid_range
      CHECK (commission_bps >= 0 AND commission_bps <= 3000);
    RAISE NOTICE '✓ Constraint de validación de commission_bps creado (0..3000 bps)';
  ELSE
    RAISE NOTICE '✓ Constraint de validación ya existe';
  END IF;
END $ensure_commission$;

-- Helper function para formatear porcentaje en descriptions
CREATE OR REPLACE FUNCTION public._format_percentage(p_rate numeric)
RETURNS text
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
  -- Convierte 0.15 -> "15%", 0.175 -> "17.5%"
  RETURN trim(trailing '.' FROM trim(trailing '0' FROM to_char(p_rate * 100, 'FM999990.99'))) || '%';
END;
$$;

-- =====================================================================
-- PASO 1: FUNCIÓN DEFINITIVA CON COMISIÓN DINÁMICA
-- =====================================================================

CREATE OR REPLACE FUNCTION public.process_order_payment_final()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  -- IDs de cuentas involucradas
  v_restaurant_account_id uuid;
  v_delivery_account_id uuid;
  v_platform_revenue_account_id uuid;
  v_platform_payables_account_id uuid;
  
  -- Variables para user_id del restaurant
  v_restaurant_user_id uuid;
  
  -- Variables financieras
  v_subtotal numeric;
  v_delivery_fee numeric;
  v_total numeric;
  
  -- Comisión dinámica
  v_commission_bps integer;
  v_commission_rate numeric; -- 0.00 .. 0.30
  v_commission_pct_display text;
  
  -- Montos calculados
  v_platform_commission numeric;
  v_restaurant_net numeric;
  v_delivery_earning numeric;
  v_platform_delivery_margin numeric;
  
  -- Control de idempotencia
  v_already_processed boolean;
BEGIN
  -- ==========================================
  -- GUARD: Solo procesar transición a delivered
  -- ==========================================
  IF NOT (NEW.status = 'delivered' AND (OLD.status IS DISTINCT FROM 'delivered')) THEN
    RETURN NEW;
  END IF;
  
  -- ==========================================
  -- IDEMPOTENCIA: Verificar si ya procesamos esta orden
  -- ==========================================
  SELECT EXISTS(
    SELECT 1 FROM public.account_transactions
    WHERE order_id = NEW.id AND type IN ('ORDER_REVENUE', 'PLATFORM_COMMISSION')
    LIMIT 1
  ) INTO v_already_processed;
  
  IF v_already_processed THEN
    RAISE NOTICE 'Orden % ya procesada, saltando...', NEW.id;
    RETURN NEW;
  END IF;
  
  -- ==========================================
  -- RESOLVER CUENTAS PARTICIPANTES
  -- ==========================================
  
  -- 1. Restaurante: obtener user_id y luego su cuenta de tipo 'restaurant'
  SELECT r.user_id INTO v_restaurant_user_id
  FROM public.restaurants r
  WHERE r.id = NEW.restaurant_id;
  
  IF v_restaurant_user_id IS NULL THEN
    RAISE EXCEPTION 'Restaurant % no tiene user_id vinculado', NEW.restaurant_id;
  END IF;
  
  SELECT a.id INTO v_restaurant_account_id
  FROM public.accounts a
  WHERE a.user_id = v_restaurant_user_id AND a.account_type = 'restaurant'
  ORDER BY a.created_at ASC
  LIMIT 1;
  
  -- 2. Repartidor: opcional (puede ser NULL si es pickup)
  IF NEW.delivery_agent_id IS NOT NULL THEN
    SELECT a.id INTO v_delivery_account_id
    FROM public.accounts a
    WHERE a.user_id = NEW.delivery_agent_id AND a.account_type = 'delivery_agent'
    ORDER BY a.created_at ASC
    LIMIT 1;
  END IF;
  
  -- 3. Plataforma Revenue: por account_type
  SELECT a.id INTO v_platform_revenue_account_id
  FROM public.accounts a
  WHERE a.account_type = 'platform_revenue'
  ORDER BY a.created_at ASC
  LIMIT 1;
  
  -- 4. Plataforma Payables: por account_type
  SELECT a.id INTO v_platform_payables_account_id
  FROM public.accounts a
  WHERE a.account_type = 'platform_payables'
  ORDER BY a.created_at ASC
  LIMIT 1;
  
  -- Validar cuentas críticas
  IF v_restaurant_account_id IS NULL THEN
    RAISE EXCEPTION 'No se encontró cuenta restaurant para user_id %', v_restaurant_user_id;
  END IF;
  IF v_platform_revenue_account_id IS NULL THEN
    RAISE EXCEPTION 'No se encontró cuenta platform_revenue';
  END IF;
  IF v_platform_payables_account_id IS NULL THEN
    RAISE EXCEPTION 'No se encontró cuenta platform_payables';
  END IF;
  IF NEW.delivery_agent_id IS NOT NULL AND v_delivery_account_id IS NULL THEN
    RAISE EXCEPTION 'No se encontró cuenta delivery_agent para user_id %', NEW.delivery_agent_id;
  END IF;
  
  -- ==========================================
  -- LEER COMISIÓN DINÁMICA DEL RESTAURANTE
  -- ==========================================
  SELECT COALESCE(r.commission_bps, 1500) INTO v_commission_bps
  FROM public.restaurants r
  WHERE r.id = NEW.restaurant_id;
  
  -- Clamp 0..3000 por seguridad (aunque el constraint ya lo valida)
  v_commission_bps := GREATEST(0, LEAST(v_commission_bps, 3000));
  
  -- Convertir basis points a rate decimal (1500 bps -> 0.15)
  v_commission_rate := v_commission_bps::numeric / 10000.0;
  v_commission_pct_display := public._format_percentage(v_commission_rate);
  
  -- ==========================================
  -- CALCULAR FINANCIALS
  -- ==========================================
  v_total := NEW.total_amount;
  v_delivery_fee := COALESCE(NEW.delivery_fee, 0);
  v_subtotal := v_total - v_delivery_fee;
  
  -- Comisión plataforma: % dinámico del subtotal
  v_platform_commission := ROUND(v_subtotal * v_commission_rate, 2);
  
  -- Neto para restaurante: subtotal menos comisión
  v_restaurant_net := v_subtotal - v_platform_commission;
  
  -- Split delivery: 85% repartidor, 15% plataforma
  v_delivery_earning := ROUND(v_delivery_fee * 0.85, 2);
  v_platform_delivery_margin := v_delivery_fee - v_delivery_earning;
  
  -- ==========================================
  -- CREAR TRANSACCIONES SEGÚN MÉTODO DE PAGO
  -- ==========================================
  
  IF NEW.payment_method = 'cash' THEN
    -- ========================================
    -- FLUJO EFECTIVO
    -- ========================================
    -- El repartidor cobra el efectivo y debe liquidarlo
    
    -- 1. Restaurante: ingreso bruto
    INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
    VALUES (
      v_restaurant_account_id,
      'ORDER_REVENUE',
      v_subtotal,
      format('Ingreso pedido #%s', NEW.id),
      NEW.id,
      jsonb_build_object(
        'subtotal', v_subtotal,
        'commission_bps', v_commission_bps,
        'commission_rate', v_commission_rate
      ),
      NOW()
    );
    
    -- 2. Restaurante: pagar comisión
    INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
    VALUES (
      v_restaurant_account_id,
      'PLATFORM_COMMISSION',
      -v_platform_commission,
      format('Comisión %s pedido #%s', v_commission_pct_display, NEW.id),
      NEW.id,
      jsonb_build_object(
        'subtotal', v_subtotal,
        'commission_bps', v_commission_bps,
        'commission_rate', v_commission_rate,
        'commission_amount', v_platform_commission
      ),
      NOW()
    );
    
    -- 3. Repartidor: ganancia delivery
    IF v_delivery_account_id IS NOT NULL THEN
      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        v_delivery_account_id,
        'DELIVERY_EARNING',
        v_delivery_earning,
        format('Ganancia delivery pedido #%s (85%%)', NEW.id),
        NEW.id,
        jsonb_build_object('delivery_fee', v_delivery_fee, 'earning_rate', 0.85),
        NOW()
      );
      
      -- 4. Repartidor: efectivo recolectado (pasivo negativo)
      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        v_delivery_account_id,
        'CASH_COLLECTED',
        -v_total,
        format('Efectivo cobrado pedido #%s', NEW.id),
        NEW.id,
        jsonb_build_object('total_collected', v_total),
        NOW()
      );
    END IF;
    
    -- 5. Plataforma: comisión
    INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
    VALUES (
      v_platform_revenue_account_id,
      'PLATFORM_COMMISSION',
      v_platform_commission,
      format('Comisión %s pedido #%s', v_commission_pct_display, NEW.id),
      NEW.id,
      jsonb_build_object(
        'subtotal', v_subtotal,
        'commission_bps', v_commission_bps,
        'commission_rate', v_commission_rate
      ),
      NOW()
    );
    
    -- 6. Plataforma: margen delivery
    IF v_platform_delivery_margin > 0 THEN
      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_DELIVERY_MARGIN',
        v_platform_delivery_margin,
        format('Margen delivery pedido #%s (15%%)', NEW.id),
        NEW.id,
        jsonb_build_object('delivery_fee', v_delivery_fee, 'margin_rate', 0.15),
        NOW()
      );
    END IF;
    
  ELSE
    -- ========================================
    -- FLUJO TARJETA
    -- ========================================
    -- La plataforma recibe el dinero y lo debe a socios (Balance Cero)
    
    -- 1. Restaurante: ingreso bruto
    INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
    VALUES (
      v_restaurant_account_id,
      'ORDER_REVENUE',
      v_subtotal,
      format('Ingreso pedido #%s', NEW.id),
      NEW.id,
      jsonb_build_object(
        'subtotal', v_subtotal,
        'commission_bps', v_commission_bps,
        'commission_rate', v_commission_rate
      ),
      NOW()
    );
    
    -- 2. Restaurante: pagar comisión
    INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
    VALUES (
      v_restaurant_account_id,
      'PLATFORM_COMMISSION',
      -v_platform_commission,
      format('Comisión %s pedido #%s', v_commission_pct_display, NEW.id),
      NEW.id,
      jsonb_build_object(
        'subtotal', v_subtotal,
        'commission_bps', v_commission_bps,
        'commission_rate', v_commission_rate,
        'commission_amount', v_platform_commission
      ),
      NOW()
    );
    
    -- 3. Repartidor: ganancia delivery
    IF v_delivery_account_id IS NOT NULL THEN
      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        v_delivery_account_id,
        'DELIVERY_EARNING',
        v_delivery_earning,
        format('Ganancia delivery pedido #%s (85%%)', NEW.id),
        NEW.id,
        jsonb_build_object('delivery_fee', v_delivery_fee, 'earning_rate', 0.85),
        NOW()
      );
    END IF;
    
    -- 4. Plataforma Payables: dinero recibido por tarjeta (pasivo negativo)
    INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
    VALUES (
      v_platform_payables_account_id,
      'CASH_COLLECTED',
      -v_total,
      format('Pago tarjeta pedido #%s', NEW.id),
      NEW.id,
      jsonb_build_object('total_received', v_total, 'payment_method', 'card'),
      NOW()
    );
    
    -- 5. Plataforma Revenue: comisión
    INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
    VALUES (
      v_platform_revenue_account_id,
      'PLATFORM_COMMISSION',
      v_platform_commission,
      format('Comisión %s pedido #%s', v_commission_pct_display, NEW.id),
      NEW.id,
      jsonb_build_object(
        'subtotal', v_subtotal,
        'commission_bps', v_commission_bps,
        'commission_rate', v_commission_rate
      ),
      NOW()
    );
    
    -- 6. Plataforma Revenue: margen delivery
    IF v_platform_delivery_margin > 0 THEN
      INSERT INTO public.account_transactions (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_DELIVERY_MARGIN',
        v_platform_delivery_margin,
        format('Margen delivery pedido #%s (15%%)', NEW.id),
        NEW.id,
        jsonb_build_object('delivery_fee', v_delivery_fee, 'margin_rate', 0.15),
        NOW()
      );
    END IF;
  END IF;
  
  -- ==========================================
  -- RECALCULAR BALANCES (Authoritative via SUM)
  -- ==========================================
  UPDATE public.accounts
  SET balance = (SELECT COALESCE(SUM(amount), 0) FROM public.account_transactions WHERE account_id = v_restaurant_account_id),
      updated_at = NOW()
  WHERE id = v_restaurant_account_id;
  
  IF v_delivery_account_id IS NOT NULL THEN
    UPDATE public.accounts
    SET balance = (SELECT COALESCE(SUM(amount), 0) FROM public.account_transactions WHERE account_id = v_delivery_account_id),
        updated_at = NOW()
    WHERE id = v_delivery_account_id;
  END IF;
  
  UPDATE public.accounts
  SET balance = (SELECT COALESCE(SUM(amount), 0) FROM public.account_transactions WHERE account_id = v_platform_revenue_account_id),
      updated_at = NOW()
  WHERE id = v_platform_revenue_account_id;
  
  UPDATE public.accounts
  SET balance = (SELECT COALESCE(SUM(amount), 0) FROM public.account_transactions WHERE account_id = v_platform_payables_account_id),
      updated_at = NOW()
  WHERE id = v_platform_payables_account_id;
  
  RAISE NOTICE '✓ Orden % procesada con comisión dinámica % (%)', NEW.id, v_commission_pct_display, v_commission_bps;
  
  RETURN NEW;
END;
$$;

-- =====================================================================
-- PASO 2: CREAR EL ÚNICO TRIGGER ACTIVO
-- =====================================================================

CREATE TRIGGER trigger_process_order_payment_final
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.process_order_payment_final();

-- =====================================================================
-- PASO 3: VERIFICACIÓN POST-INSTALACIÓN
-- =====================================================================

DO $verify$
DECLARE
  v_trigger_count integer;
  v_function_count integer;
BEGIN
  -- Contar triggers activos en orders relacionados con payment
  SELECT COUNT(*) INTO v_trigger_count
  FROM information_schema.triggers
  WHERE event_object_table = 'orders'
    AND trigger_name ILIKE '%payment%';
  
  -- Contar funciones relacionadas con order payment
  SELECT COUNT(*) INTO v_function_count
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public'
    AND p.proname ILIKE '%process%order%payment%';
  
  RAISE NOTICE '=================================================================';
  RAISE NOTICE '✓ INSTALACIÓN COMPLETADA';
  RAISE NOTICE '=================================================================';
  RAISE NOTICE 'Triggers activos en orders (payment): %', v_trigger_count;
  RAISE NOTICE 'Funciones de payment activas: %', v_function_count;
  
  IF v_trigger_count = 1 AND v_function_count = 1 THEN
    RAISE NOTICE '✓✓ ÉXITO: Solo hay 1 trigger y 1 función (configuración correcta)';
  ELSE
    RAISE WARNING '⚠ ADVERTENCIA: Se esperaba 1 trigger y 1 función, revise manualmente';
  END IF;
  
  RAISE NOTICE '=================================================================';
  RAISE NOTICE 'Función activa: process_order_payment_final()';
  RAISE NOTICE 'Trigger activo: trigger_process_order_payment_final';
  RAISE NOTICE 'Comportamiento:';
  RAISE NOTICE '  - Lee restaurants.commission_bps dinámicamente';
  RAISE NOTICE '  - Default: 1500 bps (15%%)';
  RAISE NOTICE '  - Rango válido: 0..3000 bps (0%%..30%%)';
  RAISE NOTICE '  - Escribe description y metadata en TODAS las transacciones';
  RAISE NOTICE '  - Mantiene Balance Cero para cash y card';
  RAISE NOTICE '  - Idempotente: no duplica si se re-entrega una orden';
  RAISE NOTICE '=================================================================';
END $verify$;

-- Mostrar trigger activo
SELECT 
  trigger_name,
  event_manipulation,
  action_timing,
  action_statement
FROM information_schema.triggers
WHERE event_object_table = 'orders'
  AND trigger_name ILIKE '%payment%';

-- Fin del script
