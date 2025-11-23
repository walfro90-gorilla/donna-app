-- ============================================================================
-- VALIDACIÓN: Sistema de Transacciones Balance 0
-- ============================================================================
-- Este script valida que el sistema de transacciones esté configurado correctamente
-- y funcione según lo esperado
-- ============================================================================

BEGIN;

\echo '========================================'
\echo 'VALIDACIÓN DEL SISTEMA DE TRANSACCIONES'
\echo '========================================'
\echo ''

-- ============================================================================
-- 1. VALIDAR TRIGGER EXISTE Y ESTÁ ACTIVO
-- ============================================================================

\echo '1️⃣  VALIDANDO TRIGGER...'
\echo ''

DO $$
DECLARE
  v_trigger_exists boolean;
  v_function_exists boolean;
BEGIN
  -- Verificar que existe el trigger
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'trg_on_order_delivered_process_v3'
  ) INTO v_trigger_exists;
  
  -- Verificar que existe la función
  SELECT EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'process_order_delivery_v3'
  ) INTO v_function_exists;
  
  IF v_trigger_exists AND v_function_exists THEN
    RAISE NOTICE '✅ Trigger "trg_on_order_delivered_process_v3" ACTIVO';
    RAISE NOTICE '✅ Función "process_order_delivery_v3()" EXISTE';
  ELSE
    RAISE WARNING '❌ Sistema NO configurado correctamente:';
    IF NOT v_trigger_exists THEN
      RAISE WARNING '   - Trigger NO existe';
    END IF;
    IF NOT v_function_exists THEN
      RAISE WARNING '   - Función NO existe';
    END IF;
  END IF;
END $$;

\echo ''

-- ============================================================================
-- 2. VALIDAR CONSTRAINT DE UNICIDAD EXISTE
-- ============================================================================

\echo '2️⃣  VALIDANDO CONSTRAINT DE UNICIDAD...'
\echo ''

DO $$
DECLARE
  v_constraint_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'uq_account_txn_order_account_type'
  ) INTO v_constraint_exists;
  
  IF v_constraint_exists THEN
    RAISE NOTICE '✅ Constraint "uq_account_txn_order_account_type" EXISTE';
    RAISE NOTICE '   (Previene transacciones duplicadas)';
  ELSE
    RAISE WARNING '❌ Constraint "uq_account_txn_order_account_type" NO EXISTE';
    RAISE WARNING '   Ejecutar: ALTER TABLE account_transactions ADD CONSTRAINT uq_account_txn_order_account_type UNIQUE (order_id, account_id, type);';
  END IF;
END $$;

\echo ''

-- ============================================================================
-- 3. VALIDAR TIPOS DE TRANSACCIONES VÁLIDOS
-- ============================================================================

\echo '3️⃣  VALIDANDO TIPOS DE TRANSACCIONES...'
\echo ''

DO $$
DECLARE
  rec RECORD;
  v_invalid_count integer := 0;
  v_valid_types text[] := ARRAY[
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
  ];
BEGIN
  -- Buscar tipos NO válidos
  FOR rec IN 
    SELECT DISTINCT type, COUNT(*) as count
    FROM account_transactions
    WHERE type != ALL(v_valid_types)
    GROUP BY type
  LOOP
    v_invalid_count := v_invalid_count + 1;
    RAISE WARNING '❌ Tipo INVÁLIDO encontrado: "%" (% transacciones)', rec.type, rec.count;
  END LOOP;
  
  IF v_invalid_count = 0 THEN
    RAISE NOTICE '✅ Todos los tipos de transacciones son VÁLIDOS';
  ELSE
    RAISE WARNING '❌ Se encontraron % tipos INVÁLIDOS - Ejecutar script de limpieza', v_invalid_count;
  END IF;
END $$;

\echo ''

-- ============================================================================
-- 4. VALIDAR BALANCE = 0 POR ORDEN
-- ============================================================================

\echo '4️⃣  VALIDANDO BALANCE POR ORDEN...'
\echo ''

DO $$
DECLARE
  rec RECORD;
  v_total_orders integer;
  v_unbalanced_count integer := 0;
BEGIN
  -- Contar órdenes con transacciones
  SELECT COUNT(DISTINCT order_id) INTO v_total_orders
  FROM account_transactions
  WHERE order_id IS NOT NULL;
  
  RAISE NOTICE '📊 Total órdenes con transacciones: %', v_total_orders;
  
  -- Buscar órdenes con desbalance
  FOR rec IN 
    SELECT 
      LEFT(order_id::text, 8) as order_short,
      SUM(amount) as balance,
      COUNT(*) as tx_count
    FROM account_transactions
    WHERE order_id IS NOT NULL
    GROUP BY order_id
    HAVING ABS(SUM(amount)) > 0.01
    ORDER BY ABS(SUM(amount)) DESC
    LIMIT 10
  LOOP
    v_unbalanced_count := v_unbalanced_count + 1;
    RAISE WARNING '❌ Orden #% con desbalance: $% (% transacciones)', 
      rec.order_short, ROUND(rec.balance, 2), rec.tx_count;
  END LOOP;
  
  IF v_unbalanced_count = 0 THEN
    RAISE NOTICE '✅ Todas las órdenes tienen BALANCE = 0';
  ELSE
    RAISE WARNING '❌ % órdenes con desbalance detectadas', v_unbalanced_count;
    RAISE WARNING '   Ejecutar script de limpieza: 2025-01-18_FIX_card_payment_transactions_balance_zero.sql';
  END IF;
END $$;

\echo ''

-- ============================================================================
-- 5. VALIDAR BALANCE GLOBAL
-- ============================================================================

\echo '5️⃣  VALIDANDO BALANCE GLOBAL...'
\echo ''

DO $$
DECLARE
  v_global_balance numeric;
BEGIN
  SELECT COALESCE(SUM(amount), 0) INTO v_global_balance
  FROM account_transactions;
  
  IF ABS(v_global_balance) < 0.01 THEN
    RAISE NOTICE '✅ Balance global = $% (CORRECTO)', ROUND(v_global_balance, 2);
  ELSE
    RAISE WARNING '❌ Balance global = $% (DEBERÍA SER $0.00)', ROUND(v_global_balance, 2);
    RAISE WARNING '   Sistema DESBALANCEADO - Ejecutar script de limpieza';
  END IF;
END $$;

\echo ''

-- ============================================================================
-- 6. VALIDAR BALANCE POR TIPO DE CUENTA
-- ============================================================================

\echo '6️⃣  BALANCE POR TIPO DE CUENTA...'
\echo ''

DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT 
      a.account_type,
      COUNT(DISTINCT a.id) as account_count,
      COALESCE(SUM(at.amount), 0) as total_balance
    FROM accounts a
    LEFT JOIN account_transactions at ON at.account_id = a.id
    WHERE a.account_type IN ('restaurant', 'delivery_agent', 'platform_revenue', 'platform_payables')
    GROUP BY a.account_type
    ORDER BY a.account_type
  LOOP
    RAISE NOTICE '   % (% cuentas): $%', 
      RPAD(rec.account_type, 20), 
      rec.account_count,
      ROUND(rec.total_balance, 2);
  END LOOP;
END $$;

\echo ''

-- ============================================================================
-- 7. VALIDAR ESTRUCTURA DE TRANSACCIONES PARA ÓRDENES ENTREGADAS
-- ============================================================================

\echo '7️⃣  VALIDANDO ESTRUCTURA DE TRANSACCIONES...'
\echo ''

DO $$
DECLARE
  rec RECORD;
  v_orders_checked integer := 0;
  v_orders_incomplete integer := 0;
BEGIN
  -- Verificar últimas 10 órdenes entregadas
  FOR rec IN 
    SELECT 
      o.id,
      LEFT(o.id::text, 8) as order_short,
      o.payment_method,
      o.total_amount,
      (SELECT COUNT(*) FROM account_transactions WHERE order_id = o.id AND type = 'RESTAURANT_PAYABLE') as has_restaurant,
      (SELECT COUNT(*) FROM account_transactions WHERE order_id = o.id AND type = 'PLATFORM_COMMISSION') as has_commission,
      (SELECT COUNT(*) FROM account_transactions WHERE order_id = o.id AND type = 'DELIVERY_EARNING') as has_delivery,
      (SELECT COUNT(*) FROM account_transactions WHERE order_id = o.id AND type = 'CASH_COLLECTED') as has_collected
    FROM orders o
    WHERE o.status = 'delivered'
    ORDER BY o.created_at DESC
    LIMIT 10
  LOOP
    v_orders_checked := v_orders_checked + 1;
    
    IF rec.has_restaurant = 0 OR rec.has_commission = 0 OR rec.has_delivery = 0 OR rec.has_collected = 0 THEN
      v_orders_incomplete := v_orders_incomplete + 1;
      RAISE WARNING '❌ Orden #% incompleta (method: %): R:% C:% D:% Coll:%', 
        rec.order_short,
        rec.payment_method,
        rec.has_restaurant,
        rec.has_commission,
        rec.has_delivery,
        rec.has_collected;
    END IF;
  END LOOP;
  
  IF v_orders_incomplete = 0 THEN
    RAISE NOTICE '✅ Las últimas % órdenes entregadas tienen estructura COMPLETA', v_orders_checked;
  ELSE
    RAISE WARNING '❌ % de % órdenes tienen estructura INCOMPLETA', v_orders_incomplete, v_orders_checked;
  END IF;
END $$;

\echo ''
\echo '========================================'
\echo 'RESUMEN DE VALIDACIÓN'
\echo '========================================'

DO $$
DECLARE
  v_trigger_exists boolean;
  v_constraint_exists boolean;
  v_invalid_types integer;
  v_unbalanced_orders integer;
  v_global_balance numeric;
  v_all_ok boolean := true;
BEGIN
  -- Trigger
  SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_on_order_delivered_process_v3') INTO v_trigger_exists;
  
  -- Constraint
  SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_account_txn_order_account_type') INTO v_constraint_exists;
  
  -- Tipos inválidos
  SELECT COUNT(DISTINCT type) INTO v_invalid_types
  FROM account_transactions
  WHERE type NOT IN (
    'ORDER_REVENUE', 'PLATFORM_COMMISSION', 'DELIVERY_EARNING', 'CASH_COLLECTED',
    'SETTLEMENT_PAYMENT', 'SETTLEMENT_RECEPTION', 'RESTAURANT_PAYABLE', 'DELIVERY_PAYABLE',
    'PLATFORM_DELIVERY_MARGIN', 'PLATFORM_NOT_DELIVERED_REFUND', 'CLIENT_DEBT'
  );
  
  -- Órdenes desbalanceadas
  SELECT COUNT(*) INTO v_unbalanced_orders
  FROM (
    SELECT order_id, SUM(amount) as balance
    FROM account_transactions
    WHERE order_id IS NOT NULL
    GROUP BY order_id
    HAVING ABS(SUM(amount)) > 0.01
  ) x;
  
  -- Balance global
  SELECT COALESCE(SUM(amount), 0) INTO v_global_balance FROM account_transactions;
  
  -- Validar todo
  IF NOT v_trigger_exists THEN
    RAISE WARNING '❌ TRIGGER NO CONFIGURADO';
    v_all_ok := false;
  END IF;
  
  IF NOT v_constraint_exists THEN
    RAISE WARNING '❌ CONSTRAINT NO CONFIGURADO';
    v_all_ok := false;
  END IF;
  
  IF v_invalid_types > 0 THEN
    RAISE WARNING '❌ TIPOS INVÁLIDOS: %', v_invalid_types;
    v_all_ok := false;
  END IF;
  
  IF v_unbalanced_orders > 0 THEN
    RAISE WARNING '❌ ÓRDENES DESBALANCEADAS: %', v_unbalanced_orders;
    v_all_ok := false;
  END IF;
  
  IF ABS(v_global_balance) >= 0.01 THEN
    RAISE WARNING '❌ BALANCE GLOBAL: $%', ROUND(v_global_balance, 2);
    v_all_ok := false;
  END IF;
  
  IF v_all_ok THEN
    RAISE NOTICE '';
    RAISE NOTICE '🎉 ✅ SISTEMA COMPLETAMENTE VÁLIDO';
    RAISE NOTICE '';
  ELSE
    RAISE WARNING '';
    RAISE WARNING '⚠️  SISTEMA REQUIERE CORRECCIONES';
    RAISE WARNING 'Ejecutar: sql_migrations/2025-01-18_FIX_card_payment_transactions_balance_zero.sql';
    RAISE WARNING '';
  END IF;
END $$;

\echo '========================================'

COMMIT;
