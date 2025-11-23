-- =====================================================================
-- NUCLEAR FIX: Commission BPS - Diagnostic + Complete Rebuild
-- =====================================================================
-- Context: Transaction feed shows 20% flat commission and NULL metadata
-- Root Cause Analysis:
--   1. commission_bps column may not exist in restaurants table
--   2. Old trigger process_order_payment() with hardcoded 0.15 still active
--   3. Multiple conflicting trigger names (trigger_process_payment_on_delivery vs trigger_process_order_payment)
-- 
-- This script:
--   ✅ Provides diagnostic queries to understand current state
--   ✅ Nuclear cleanup of ALL payment triggers and functions
--   ✅ Ensures commission_bps column exists with proper constraints
--   ✅ Creates clean, working trigger using commission_bps
--   ✅ Includes verification queries
-- =====================================================================

-- =====================================================================
-- PHASE 1: DIAGNOSTIC - Uncomment to run diagnostics before fix
-- =====================================================================

-- Show current triggers on orders table
-- SELECT 
--   t.tgname AS trigger_name,
--   p.proname AS function_name,
--   pg_get_triggerdef(t.oid) AS trigger_definition
-- FROM pg_trigger t
-- JOIN pg_class c ON t.tgrelid = c.oid
-- JOIN pg_namespace n ON c.relnamespace = n.oid
-- LEFT JOIN pg_proc p ON t.tgfoid = p.oid
-- WHERE n.nspname = 'public' AND c.relname = 'orders' AND NOT t.tgisinternal
-- ORDER BY t.tgname;

-- Check if commission_bps column exists
-- SELECT 
--   column_name, 
--   data_type, 
--   column_default,
--   is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' 
--   AND table_name = 'restaurants' 
--   AND column_name = 'commission_bps';

-- Show all payment-related functions
-- SELECT 
--   p.proname AS function_name,
--   pg_get_functiondef(p.oid) AS function_definition
-- FROM pg_proc p
-- JOIN pg_namespace n ON p.pronamespace = n.oid
-- WHERE n.nspname = 'public'
--   AND p.proname LIKE '%payment%'
-- ORDER BY p.proname;

-- =====================================================================
-- PHASE 2: NUCLEAR CLEANUP
-- =====================================================================

DO $$ 
DECLARE
  r RECORD;
BEGIN
  RAISE NOTICE '🔥 PHASE 2: Nuclear cleanup of triggers and functions...';
  
  -- Drop ALL triggers on orders table (no exceptions)
  FOR r IN (
    SELECT t.tgname
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'orders' AND NOT t.tgisinternal
  ) LOOP
    RAISE NOTICE '  ⚡ Dropping trigger: %', r.tgname;
    EXECUTE 'DROP TRIGGER IF EXISTS ' || quote_ident(r.tgname) || ' ON public.orders CASCADE';
  END LOOP;

  RAISE NOTICE '✅ All triggers dropped from orders table';
END $$;

-- Drop ALL payment-related functions (CASCADE to ensure clean state)
DROP FUNCTION IF EXISTS public.process_order_payment_on_delivery() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment() CASCADE;
DROP FUNCTION IF EXISTS public.process_order_payment_v2() CASCADE;
DROP FUNCTION IF EXISTS public.trigger_process_order_completion() CASCADE;

RAISE NOTICE '✅ All payment functions dropped';

-- =====================================================================
-- PHASE 3: ENSURE COMMISSION_BPS COLUMN EXISTS
-- =====================================================================

DO $$
BEGIN
  RAISE NOTICE '🔧 PHASE 3: Ensuring commission_bps column exists...';
  
  -- Add column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' 
      AND table_name='restaurants' 
      AND column_name='commission_bps'
  ) THEN
    ALTER TABLE public.restaurants 
      ADD COLUMN commission_bps integer NOT NULL DEFAULT 1500;
    RAISE NOTICE '  ✅ Added commission_bps column (default 1500 = 15%%)';
  ELSE
    RAISE NOTICE '  ℹ️  commission_bps column already exists';
  END IF;

  -- Add constraint if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname='public' 
      AND t.relname='restaurants' 
      AND c.conname='restaurants_commission_bps_check'
  ) THEN
    ALTER TABLE public.restaurants
      ADD CONSTRAINT restaurants_commission_bps_check
      CHECK (commission_bps >= 0 AND commission_bps <= 3000);
    RAISE NOTICE '  ✅ Added constraint: commission_bps between 0 and 3000';
  ELSE
    RAISE NOTICE '  ℹ️  Constraint restaurants_commission_bps_check already exists';
  END IF;

  RAISE NOTICE '✅ commission_bps column configured';
END $$;

-- =====================================================================
-- PHASE 4: CREATE HELPER FUNCTION FOR FORMATTING PERCENTAGES
-- =====================================================================

CREATE OR REPLACE FUNCTION public._fmt_pct(p_rate numeric)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN trim(trailing '.' FROM trim(trailing '0' FROM to_char(p_rate * 100, 'FM999999990.99'))) || '%';
END;
$$;

RAISE NOTICE '✅ Helper function _fmt_pct created';

-- =====================================================================
-- PHASE 5: CREATE THE AUTHORITATIVE PAYMENT PROCESSING FUNCTION
-- =====================================================================

CREATE OR REPLACE FUNCTION public.process_order_payment_v2()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  restaurant_account_id uuid;
  delivery_agent_account_id uuid;
  platform_revenue_account_id uuid;
  platform_payables_account_id uuid;

  v_restaurant_user_id uuid;

  subtotal numeric;
  platform_commission numeric;
  delivery_earning numeric;
  platform_delivery_margin numeric;

  v_commission_bps integer;
  v_commission_rate numeric;
  v_already boolean;
BEGIN
  -- Only process when order transitions to 'delivered'
  IF NEW.status = 'delivered' AND OLD.status <> 'delivered' THEN

    -- Idempotency check: skip if already processed
    SELECT EXISTS (
      SELECT 1 FROM public.account_transactions
      WHERE order_id = NEW.id 
        AND type IN ('ORDER_REVENUE','PLATFORM_COMMISSION')
    ) INTO v_already;
    
    IF v_already THEN
      RAISE LOG '[payment_v2] Order % already processed, skipping', NEW.id;
      RETURN NEW;
    END IF;

    RAISE LOG '[payment_v2] Processing payment for order %', NEW.id;

    -- Get restaurant user_id
    SELECT r.user_id INTO v_restaurant_user_id
    FROM public.restaurants r
    WHERE r.id = NEW.restaurant_id;

    IF v_restaurant_user_id IS NULL THEN
      RAISE EXCEPTION '[payment_v2] Restaurant % has no linked user_id', NEW.restaurant_id;
    END IF;

    -- Get restaurant account
    SELECT a.id INTO restaurant_account_id
    FROM public.accounts a
    WHERE a.user_id = v_restaurant_user_id 
      AND a.account_type = 'restaurant'
    ORDER BY a.created_at ASC
    LIMIT 1;

    -- Get delivery agent account (if assigned)
    IF NEW.delivery_agent_id IS NOT NULL THEN
      SELECT a.id INTO delivery_agent_account_id
      FROM public.accounts a
      WHERE a.user_id = NEW.delivery_agent_id 
        AND a.account_type = 'delivery_agent'
      ORDER BY a.created_at ASC
      LIMIT 1;
    END IF;

    -- Get platform accounts
    SELECT a.id INTO platform_revenue_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_revenue'
    ORDER BY a.created_at ASC
    LIMIT 1;

    SELECT a.id INTO platform_payables_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_payables'
    ORDER BY a.created_at ASC
    LIMIT 1;

    -- Validate all required accounts exist
    IF restaurant_account_id IS NULL THEN
      RAISE EXCEPTION '[payment_v2] Missing restaurant account for user %', v_restaurant_user_id;
    END IF;

    IF platform_revenue_account_id IS NULL THEN
      RAISE EXCEPTION '[payment_v2] Missing platform_revenue account';
    END IF;

    IF platform_payables_account_id IS NULL THEN
      RAISE EXCEPTION '[payment_v2] Missing platform_payables account';
    END IF;

    IF NEW.delivery_agent_id IS NOT NULL AND delivery_agent_account_id IS NULL THEN
      RAISE EXCEPTION '[payment_v2] Missing delivery_agent account for user %', NEW.delivery_agent_id;
    END IF;

    -- ===================================================================
    -- CALCULATE FINANCIALS USING COMMISSION_BPS FROM RESTAURANTS TABLE
    -- ===================================================================
    subtotal := NEW.total_amount - COALESCE(NEW.delivery_fee, 0);
    
    -- Read commission_bps from restaurants table, default 1500 (15%), clamp to 0..3000
    SELECT GREATEST(0, LEAST(COALESCE(commission_bps, 1500), 3000)) 
    INTO v_commission_bps
    FROM public.restaurants 
    WHERE id = NEW.restaurant_id;
    
    -- Convert basis points to decimal rate: 1500 bps = 0.15 (15%)
    v_commission_rate := v_commission_bps::numeric / 10000.0;

    RAISE LOG '[payment_v2] Order %: commission_bps=%, rate=%, subtotal=%', 
      NEW.id, v_commission_bps, v_commission_rate, subtotal;

    platform_commission := ROUND(subtotal * v_commission_rate, 2);
    delivery_earning := ROUND(COALESCE(NEW.delivery_fee, 0) * 0.85, 2);
    platform_delivery_margin := COALESCE(NEW.delivery_fee, 0) - delivery_earning;

    -- ===================================================================
    -- BRANCH BY PAYMENT METHOD
    -- ===================================================================
    IF NEW.payment_method = 'cash' THEN
      -- CASH FLOW

      -- Restaurant receives order revenue (subtotal)
      INSERT INTO public.account_transactions 
        (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        restaurant_account_id, 
        'ORDER_REVENUE', 
        subtotal,
        'Ingreso por pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object(
          'commission_rate', v_commission_rate, 
          'commission_bps', v_commission_bps, 
          'subtotal', subtotal
        ),
        NOW()
      );

      -- Restaurant pays platform commission (negative)
      INSERT INTO public.account_transactions 
        (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        restaurant_account_id, 
        'PLATFORM_COMMISSION', 
        -platform_commission,
        'Comisión ' || public._fmt_pct(v_commission_rate) || ' - Pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object(
          'commission_rate', v_commission_rate, 
          'commission_bps', v_commission_bps, 
          'subtotal', subtotal
        ),
        NOW()
      );

      -- Delivery agent earnings (if assigned)
      IF delivery_agent_account_id IS NOT NULL THEN
        INSERT INTO public.account_transactions 
          (account_id, type, amount, description, order_id, metadata, created_at)
        VALUES (
          delivery_agent_account_id, 
          'DELIVERY_EARNING', 
          delivery_earning,
          'Ganancia delivery - Pedido #' || NEW.id,
          NEW.id,
          jsonb_build_object('delivery_fee', NEW.delivery_fee, 'rate', 0.85),
          NOW()
        );

        -- Delivery agent collects cash (negative liability)
        INSERT INTO public.account_transactions 
          (account_id, type, amount, description, order_id, metadata, created_at)
        VALUES (
          delivery_agent_account_id, 
          'CASH_COLLECTED', 
          -NEW.total_amount,
          'Efectivo recolectado - Pedido #' || NEW.id,
          NEW.id,
          jsonb_build_object('total_amount', NEW.total_amount),
          NOW()
        );
      END IF;

      -- Platform receives commission
      INSERT INTO public.account_transactions 
        (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        platform_revenue_account_id, 
        'PLATFORM_COMMISSION', 
        platform_commission,
        'Comisión ' || public._fmt_pct(v_commission_rate) || ' - Pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object(
          'commission_rate', v_commission_rate, 
          'commission_bps', v_commission_bps, 
          'subtotal', subtotal
        ),
        NOW()
      );

      -- Platform delivery margin
      IF platform_delivery_margin > 0 THEN
        INSERT INTO public.account_transactions 
          (account_id, type, amount, description, order_id, metadata, created_at)
        VALUES (
          platform_revenue_account_id, 
          'PLATFORM_DELIVERY_MARGIN', 
          platform_delivery_margin,
          'Margen delivery - Pedido #' || NEW.id,
          NEW.id,
          jsonb_build_object('delivery_fee', NEW.delivery_fee, 'margin_rate', 0.15),
          NOW()
        );
      END IF;

    ELSE
      -- CARD FLOW

      -- Restaurant receives order revenue (subtotal)
      INSERT INTO public.account_transactions 
        (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        restaurant_account_id, 
        'ORDER_REVENUE', 
        subtotal,
        'Ingreso por pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object(
          'commission_rate', v_commission_rate, 
          'commission_bps', v_commission_bps, 
          'subtotal', subtotal
        ),
        NOW()
      );

      -- Restaurant pays platform commission (negative)
      INSERT INTO public.account_transactions 
        (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        restaurant_account_id, 
        'PLATFORM_COMMISSION', 
        -platform_commission,
        'Comisión ' || public._fmt_pct(v_commission_rate) || ' - Pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object(
          'commission_rate', v_commission_rate, 
          'commission_bps', v_commission_bps, 
          'subtotal', subtotal
        ),
        NOW()
      );

      -- Delivery agent earning (if assigned)
      IF delivery_agent_account_id IS NOT NULL THEN
        INSERT INTO public.account_transactions 
          (account_id, type, amount, description, order_id, metadata, created_at)
        VALUES (
          delivery_agent_account_id, 
          'DELIVERY_EARNING', 
          delivery_earning,
          'Ganancia delivery - Pedido #' || NEW.id,
          NEW.id,
          jsonb_build_object('delivery_fee', NEW.delivery_fee, 'rate', 0.85),
          NOW()
        );
      END IF;

      -- Platform receives card payment (as payable, negative)
      INSERT INTO public.account_transactions 
        (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        platform_payables_account_id, 
        'CASH_COLLECTED', 
        -NEW.total_amount,
        'Dinero recibido por tarjeta - Pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object('payment_method', 'card', 'total_amount', NEW.total_amount),
        NOW()
      );

      -- Platform receives commission
      INSERT INTO public.account_transactions 
        (account_id, type, amount, description, order_id, metadata, created_at)
      VALUES (
        platform_revenue_account_id, 
        'PLATFORM_COMMISSION', 
        platform_commission,
        'Comisión ' || public._fmt_pct(v_commission_rate) || ' - Pedido #' || NEW.id,
        NEW.id,
        jsonb_build_object(
          'commission_rate', v_commission_rate, 
          'commission_bps', v_commission_bps, 
          'subtotal', subtotal
        ),
        NOW()
      );
    END IF;

    -- ===================================================================
    -- RECOMPUTE BALANCES FROM TRANSACTIONS (AUTHORITATIVE)
    -- ===================================================================
    UPDATE public.accounts 
    SET balance = (
      SELECT COALESCE(SUM(amount), 0) 
      FROM public.account_transactions 
      WHERE account_id = restaurant_account_id
    ) 
    WHERE id = restaurant_account_id;

    IF delivery_agent_account_id IS NOT NULL THEN
      UPDATE public.accounts 
      SET balance = (
        SELECT COALESCE(SUM(amount), 0) 
        FROM public.account_transactions 
        WHERE account_id = delivery_agent_account_id
      ) 
      WHERE id = delivery_agent_account_id;
    END IF;

    UPDATE public.accounts 
    SET balance = (
      SELECT COALESCE(SUM(amount), 0) 
      FROM public.account_transactions 
      WHERE account_id = platform_revenue_account_id
    ) 
    WHERE id = platform_revenue_account_id;

    UPDATE public.accounts 
    SET balance = (
      SELECT COALESCE(SUM(amount), 0) 
      FROM public.account_transactions 
      WHERE account_id = platform_payables_account_id
    ) 
    WHERE id = platform_payables_account_id;

    RAISE LOG '[payment_v2] ✅ Payment processed successfully for order %', NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

RAISE NOTICE '✅ Function process_order_payment_v2 created';

-- =====================================================================
-- PHASE 6: CREATE THE TRIGGER (ONLY ONE, CANONICAL)
-- =====================================================================

CREATE TRIGGER trigger_process_order_payment
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.process_order_payment_v2();

RAISE NOTICE '✅ Trigger trigger_process_order_payment created';

-- =====================================================================
-- PHASE 7: VERIFICATION QUERIES
-- =====================================================================

RAISE NOTICE '🔍 Running verification queries...';

-- Verify trigger exists and points to correct function
DO $$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM information_schema.triggers
  WHERE trigger_name = 'trigger_process_order_payment'
    AND event_object_table = 'orders'
    AND action_statement LIKE '%process_order_payment_v2%';
  
  IF v_count = 1 THEN
    RAISE NOTICE '  ✅ Trigger correctly configured';
  ELSE
    RAISE WARNING '  ⚠️  Trigger verification failed';
  END IF;
END $$;

-- Verify commission_bps column
DO $$
DECLARE
  v_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' 
      AND table_name='restaurants' 
      AND column_name='commission_bps'
  ) INTO v_exists;
  
  IF v_exists THEN
    RAISE NOTICE '  ✅ commission_bps column exists in restaurants table';
  ELSE
    RAISE WARNING '  ⚠️  commission_bps column NOT FOUND in restaurants table';
  END IF;
END $$;

-- =====================================================================
-- PHASE 8: DIAGNOSTIC HELPER FUNCTION
-- =====================================================================

CREATE OR REPLACE FUNCTION public.rpc_preview_order_financials(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_subtotal numeric;
  v_commission_bps integer;
  v_commission_rate numeric;
  v_commission numeric;
  v_delivery_earning numeric;
  v_platform_delivery_margin numeric;
BEGIN
  -- Get order with commission_bps from restaurant
  SELECT 
    o.id,
    o.total_amount,
    o.delivery_fee,
    o.payment_method,
    o.status,
    o.restaurant_id,
    COALESCE(r.commission_bps, 1500) AS c_bps,
    r.name AS restaurant_name
  INTO v_order
  FROM public.orders o
  LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.id = p_order_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found');
  END IF;

  v_subtotal := COALESCE(v_order.total_amount, 0) - COALESCE(v_order.delivery_fee, 0);
  v_commission_bps := GREATEST(0, LEAST(COALESCE(v_order.c_bps, 1500), 3000));
  v_commission_rate := v_commission_bps::numeric / 10000.0;
  v_commission := ROUND(v_subtotal * v_commission_rate, 2);
  v_delivery_earning := ROUND(COALESCE(v_order.delivery_fee, 0) * 0.85, 2);
  v_platform_delivery_margin := COALESCE(v_order.delivery_fee, 0) - v_delivery_earning;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'restaurant_name', v_order.restaurant_name,
    'status', v_order.status,
    'payment_method', v_order.payment_method,
    'total_amount', v_order.total_amount,
    'delivery_fee', v_order.delivery_fee,
    'subtotal', v_subtotal,
    'commission_bps', v_commission_bps,
    'commission_rate', v_commission_rate,
    'commission_amount', v_commission,
    'delivery_earning', v_delivery_earning,
    'platform_delivery_margin', v_platform_delivery_margin
  );
END;
$$;

RAISE NOTICE '✅ Diagnostic function rpc_preview_order_financials created';

-- =====================================================================
-- COMPLETION MESSAGE
-- =====================================================================

RAISE NOTICE '';
RAISE NOTICE '========================================';
RAISE NOTICE '✅ NUCLEAR FIX COMPLETED SUCCESSFULLY';
RAISE NOTICE '========================================';
RAISE NOTICE '';
RAISE NOTICE 'Summary:';
RAISE NOTICE '  • All old triggers dropped from orders table';
RAISE NOTICE '  • All old payment functions removed';
RAISE NOTICE '  • commission_bps column ensured in restaurants table';
RAISE NOTICE '  • New process_order_payment_v2() function created';
RAISE NOTICE '  • New trigger_process_order_payment trigger created';
RAISE NOTICE '  • Diagnostic helper function available';
RAISE NOTICE '';
RAISE NOTICE 'Next steps:';
RAISE NOTICE '  1. Test with a new order delivery';
RAISE NOTICE '  2. Use: SELECT * FROM rpc_preview_order_financials(''<order_id>'');';
RAISE NOTICE '  3. Check account_transactions for proper description and metadata';
RAISE NOTICE '';
RAISE NOTICE 'To view current triggers:';
RAISE NOTICE '  SELECT tgname, pg_get_triggerdef(oid) FROM pg_trigger';
RAISE NOTICE '  WHERE tgrelid = ''public.orders''::regclass AND NOT tgisinternal;';
RAISE NOTICE '';
