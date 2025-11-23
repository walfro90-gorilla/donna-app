-- ============================================================================
-- FIX: Sistema de transacciones para pagos con tarjeta - Balance 0
-- ============================================================================
-- Problema identificado:
--   1. Transacciones incorrectas creadas por el webhook (ORDER_PAYMENT, PAYMENT_DEBT)
--   2. Transacciones duplicadas (PLATFORM_COMMISSION negativa, ORDER_REVENUE redundante)
--   3. Balance no da 0 por cuenta/orden
--
-- Solución:
--   1. Eliminar transacciones INCORRECTAS creadas por webhook antiguo
--   2. Asegurar que SOLO el trigger process_order_delivery_v3() crea transacciones
--   3. Validar que cada orden entregada tenga suma de transacciones = 0
-- ============================================================================

BEGIN;

-- ============================================================================
-- PASO 1: ELIMINAR TRANSACCIONES INCORRECTAS
-- ============================================================================

-- 1.1: Eliminar transacciones con tipos NO VÁLIDOS según DATABASE_SCHEMA.sql
-- Tipos válidos: ORDER_REVENUE, PLATFORM_COMMISSION, DELIVERY_EARNING, 
--                CASH_COLLECTED, SETTLEMENT_PAYMENT, SETTLEMENT_RECEPTION,
--                RESTAURANT_PAYABLE, DELIVERY_PAYABLE, PLATFORM_DELIVERY_MARGIN,
--                PLATFORM_NOT_DELIVERED_REFUND, CLIENT_DEBT

DELETE FROM public.account_transactions
WHERE type NOT IN (
  'ORDER_REVENUE',
  'PLATFORM_COMMISSION',
  'DELIVERY_EARNING',
  'CASH_COLLECTED',
  'SETTLEMENT_PAYMENT',
  'SETTLEMENT_RECEPTION',
  'RESTAURANT_PAYABLE',
  'DELIVERY_PAYABLE',
  'PLATFORM_DELIVERY_MARGIN',
  'PLATFORM_NOT_DELIVERED_REFUND',
  'CLIENT_DEBT'
);

-- 1.2: Eliminar transacciones ORDER_REVENUE cuando ya existen las de distribución
-- (Según el nuevo sistema, ORDER_REVENUE es redundante cuando hay distribución completa)
WITH orders_with_distribution AS (
  SELECT DISTINCT order_id
  FROM public.account_transactions
  WHERE type IN ('RESTAURANT_PAYABLE', 'PLATFORM_COMMISSION', 'DELIVERY_EARNING')
    AND order_id IS NOT NULL
  GROUP BY order_id
  HAVING COUNT(DISTINCT type) >= 2  -- Al menos restaurant + commission
)
DELETE FROM public.account_transactions
WHERE type = 'ORDER_REVENUE'
  AND order_id IN (SELECT order_id FROM orders_with_distribution);

-- 1.3: Eliminar transacciones PLATFORM_COMMISSION negativas duplicadas
-- (Solo debe haber una PLATFORM_COMMISSION positiva por orden)
DELETE FROM public.account_transactions
WHERE type = 'PLATFORM_COMMISSION'
  AND amount < 0;


-- ============================================================================
-- PASO 2: RECREAR TRANSACCIONES FALTANTES PARA ÓRDENES ENTREGADAS CON TARJETA
-- ============================================================================

-- 2.1: Identificar órdenes entregadas con tarjeta que NO tienen transacciones completas
WITH orders_needing_fix AS (
  SELECT 
    o.id as order_id,
    o.restaurant_id,
    o.delivery_agent_id,
    o.total_amount,
    o.subtotal,
    o.delivery_fee,
    o.payment_method,
    COUNT(at.id) as tx_count
  FROM public.orders o
  LEFT JOIN public.account_transactions at ON at.order_id = o.id
  WHERE o.status = 'delivered'
    AND o.payment_method = 'card'
  GROUP BY o.id, o.restaurant_id, o.delivery_agent_id, o.total_amount, o.subtotal, o.delivery_fee, o.payment_method
  HAVING COUNT(at.id) < 4  -- Debería tener al menos 4: RESTAURANT_PAYABLE, PLATFORM_COMMISSION, DELIVERY_EARNING, CASH_COLLECTED
)
-- Eliminar transacciones existentes de esas órdenes para recrearlas limpias
DELETE FROM public.account_transactions
WHERE order_id IN (SELECT order_id FROM orders_needing_fix);

-- 2.2: Recrear transacciones usando el mismo trigger
-- Forzar re-ejecución del trigger actualizando status temporalmente
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN 
    SELECT o.id
    FROM public.orders o
    WHERE o.status = 'delivered'
      AND o.payment_method = 'card'
      AND NOT EXISTS (
        SELECT 1 FROM public.account_transactions at 
        WHERE at.order_id = o.id AND at.type = 'CASH_COLLECTED'
      )
  LOOP
    -- Temporalmente cambiar a 'preparing' y luego a 'delivered' para re-disparar el trigger
    UPDATE public.orders 
    SET status = 'preparing', updated_at = now()
    WHERE id = rec.id;
    
    -- Volver a 'delivered' - esto dispara process_order_delivery_v3()
    UPDATE public.orders 
    SET status = 'delivered', updated_at = now()
    WHERE id = rec.id;
    
    RAISE NOTICE '✅ Recreadas transacciones para orden %', rec.id;
  END LOOP;
END $$;


-- ============================================================================
-- PASO 3: VALIDAR BALANCE = 0 POR ORDEN
-- ============================================================================

-- 3.1: Verificar que todas las órdenes entregadas tengan balance 0
DO $$
DECLARE
  v_order_count integer;
  v_unbalanced_count integer;
  rec RECORD;
BEGIN
  -- Contar órdenes entregadas
  SELECT COUNT(*) INTO v_order_count
  FROM public.orders
  WHERE status = 'delivered';
  
  -- Contar órdenes con desbalance
  SELECT COUNT(*) INTO v_unbalanced_count
  FROM (
    SELECT 
      order_id,
      SUM(amount) as balance
    FROM public.account_transactions
    WHERE order_id IS NOT NULL
    GROUP BY order_id
    HAVING ABS(SUM(amount)) > 0.01  -- Tolerancia de 1 centavo por redondeo
  ) unbalanced;
  
  RAISE NOTICE '========================================';
  RAISE NOTICE 'VALIDACIÓN DE BALANCE 0';
  RAISE NOTICE '========================================';
  RAISE NOTICE '📊 Total órdenes entregadas: %', v_order_count;
  RAISE NOTICE '⚖️  Órdenes con desbalance: %', v_unbalanced_count;
  
  -- Mostrar órdenes con desbalance (primeras 10)
  IF v_unbalanced_count > 0 THEN
    RAISE NOTICE '❌ Órdenes con desbalance detectadas:';
    FOR rec IN 
      SELECT 
        LEFT(order_id::text, 8) as order_short,
        SUM(amount) as balance,
        COUNT(*) as tx_count
      FROM public.account_transactions
      WHERE order_id IS NOT NULL
      GROUP BY order_id
      HAVING ABS(SUM(amount)) > 0.01
      LIMIT 10
    LOOP
      RAISE NOTICE '   - Orden #%: Balance = $%, Transacciones = %', rec.order_short, rec.balance, rec.tx_count;
    END LOOP;
  ELSE
    RAISE NOTICE '✅ Todas las órdenes tienen balance 0';
  END IF;
  
  RAISE NOTICE '========================================';
END $$;


-- ============================================================================
-- PASO 4: VALIDAR BALANCE POR CUENTA
-- ============================================================================

DO $$
DECLARE
  rec RECORD;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'BALANCE POR TIPO DE CUENTA';
  RAISE NOTICE '========================================';
  
  FOR rec IN
    SELECT 
      a.account_type,
      COUNT(DISTINCT a.id) as cuenta_count,
      COALESCE(SUM(at.amount), 0) as total_balance
    FROM public.accounts a
    LEFT JOIN public.account_transactions at ON at.account_id = a.id
    WHERE a.account_type IN ('restaurant', 'delivery_agent', 'platform_revenue', 'platform_payables')
    GROUP BY a.account_type
    ORDER BY a.account_type
  LOOP
    RAISE NOTICE '% (%): $% MXN', 
      UPPER(rec.account_type), 
      rec.cuenta_count,
      ROUND(rec.total_balance, 2);
  END LOOP;
  
  -- Balance global
  RAISE NOTICE '----------------------------------------';
  SELECT COALESCE(SUM(amount), 0) INTO rec.total_balance
  FROM public.account_transactions;
  
  RAISE NOTICE 'BALANCE GLOBAL: $% MXN', ROUND(rec.total_balance, 2);
  
  IF ABS(rec.total_balance) < 0.01 THEN
    RAISE NOTICE '✅ Sistema en balance 0';
  ELSE
    RAISE WARNING '❌ Sistema DESBALANCEADO - Revisar transacciones';
  END IF;
  
  RAISE NOTICE '========================================';
END $$;

COMMIT;
