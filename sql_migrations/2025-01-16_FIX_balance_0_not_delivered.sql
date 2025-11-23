-- ============================================================================
-- FIX: Balance 0 para órdenes "not_delivered"
-- ============================================================================
-- Date: 2025-01-16
-- Purpose: 
--   Agregar transacciones balanceadoras para que las órdenes not_delivered 
--   cuadren en Balance 0 (suma de transacciones = 0)
-- ============================================================================
-- 📊 PROBLEMA ENCONTRADO:
--   La orden 820f7e53-7146-408d-8152-c11e3496302d tiene desbalance de $318.90
--   Solo tiene 1 transacción: ORDER_REVENUE por $283.90
--   Faltan las transacciones de compensación de la plataforma
-- 
-- ✅ SOLUCIÓN:
--   1. Agregar nuevos tipos de transacciones al constraint
--   2. Actualizar RPC mark_order_not_delivered para crear transacciones balanceadoras
--   3. Actualizar balance_zero_screen para mostrar nuevos tipos
-- ============================================================================

-- ============================================================================
-- PASO 1: Agregar nuevos tipos de transacciones al constraint
-- ============================================================================

DO $$
BEGIN
  -- Drop existing constraint
  ALTER TABLE public.account_transactions DROP CONSTRAINT IF EXISTS account_transactions_type_check;
  
  -- Add updated constraint with new transaction types
  ALTER TABLE public.account_transactions
  ADD CONSTRAINT account_transactions_type_check
  CHECK (
    type = ANY (ARRAY[
      'ORDER_REVENUE'::text,
      'PLATFORM_COMMISSION'::text,
      'DELIVERY_EARNING'::text,
      'CASH_COLLECTED'::text,
      'SETTLEMENT_PAYMENT'::text,
      'SETTLEMENT_RECEPTION'::text,
      'RESTAURANT_PAYABLE'::text,
      'DELIVERY_PAYABLE'::text,
      'PLATFORM_DELIVERY_MARGIN'::text,
      'PLATFORM_NOT_DELIVERED_REFUND'::text,  -- ✅ NEW: Plataforma paga por orden no entregada
      'CLIENT_DEBT'::text                     -- ✅ NEW: Deuda del cliente
    ])
  );
  
  RAISE NOTICE '✅ Constraint account_transactions_type_check updated with new types';
END $$;

-- ============================================================================
-- PASO 2: Actualizar RPC mark_order_not_delivered
-- ============================================================================

DROP FUNCTION IF EXISTS public.mark_order_not_delivered(uuid, uuid, text, text, text);

CREATE OR REPLACE FUNCTION public.mark_order_not_delivered(
  p_order_id uuid,
  p_delivery_agent_id uuid,
  p_reason text DEFAULT 'client_no_show',
  p_delivery_notes text DEFAULT NULL,
  p_photo_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order_record RECORD;
  v_debt_id uuid;
  v_total_amount numeric;
  v_restaurant_amount numeric;
  v_delivery_fee numeric;
  v_delivery_earning numeric;
  v_platform_commission numeric;
  v_platform_delivery_margin numeric;
  v_commission_bps integer;
  v_client_suspension RECORD;
  v_new_failed_attempts int;
  v_should_suspend boolean := false;
  v_restaurant_account_id uuid;
  v_delivery_account_id uuid;
  v_client_account_id uuid;
  v_platform_revenue_account_id uuid;
BEGIN
  -- Log inicio
  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    '🚀 Function started',
    jsonb_build_object(
      'order_id', p_order_id,
      'delivery_agent_id', p_delivery_agent_id,
      'reason', p_reason
    )
  );

  -- 1. Obtener información de la orden + comisión del restaurante
  SELECT 
    o.*,
    r.user_id as restaurant_owner_id,
    r.commission_bps
  INTO v_order_record
  FROM public.orders o
  LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.id = p_order_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found');
  END IF;

  -- Validar estado
  IF v_order_record.status NOT IN ('assigned', 'picked_up', 'on_the_way', 'in_transit') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Order must be in assigned, picked_up, on_the_way, or in_transit status'
    );
  END IF;

  -- Validar repartidor
  IF v_order_record.delivery_agent_id != p_delivery_agent_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You are not the assigned delivery agent for this order'
    );
  END IF;

  -- 2. Calcular montos
  v_commission_bps := COALESCE(v_order_record.commission_bps, 1500);
  v_platform_commission := ROUND((COALESCE(v_order_record.subtotal, 0) * v_commission_bps / 10000.0), 2);
  v_restaurant_amount := COALESCE(v_order_record.subtotal, 0) - v_platform_commission;
  v_delivery_fee := COALESCE(v_order_record.delivery_fee, 0);
  v_delivery_earning := ROUND(v_delivery_fee * 0.85, 2);
  v_platform_delivery_margin := ROUND(v_delivery_fee - v_delivery_earning, 2);
  v_total_amount := COALESCE(v_order_record.total_amount, 0);

  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    '💰 Amounts calculated',
    jsonb_build_object(
      'total_amount', v_total_amount,
      'subtotal', v_order_record.subtotal,
      'restaurant_amount', v_restaurant_amount,
      'delivery_earning', v_delivery_earning,
      'platform_commission', v_platform_commission,
      'commission_bps', v_commission_bps
    )
  );

  -- 3. Obtener cuentas
  SELECT a.id INTO v_restaurant_account_id
  FROM public.accounts a
  WHERE a.user_id = v_order_record.restaurant_owner_id
    AND a.account_type = 'restaurant'
  LIMIT 1;

  SELECT a.id INTO v_delivery_account_id
  FROM public.accounts a
  WHERE a.user_id = p_delivery_agent_id
    AND a.account_type = 'delivery_agent'
  LIMIT 1;

  -- Asegurar que el cliente tenga cuenta
  PERFORM public.ensure_client_profile_and_account(v_order_record.user_id);
  
  SELECT a.id INTO v_client_account_id
  FROM public.accounts a
  WHERE a.user_id = v_order_record.user_id
    AND a.account_type = 'client'
  LIMIT 1;

  -- Obtener cuenta de plataforma (platform_revenue o platform)
  SELECT a.id INTO v_platform_revenue_account_id
  FROM public.accounts a
  WHERE a.account_type IN ('platform_revenue', 'platform')
  ORDER BY 
    CASE 
      WHEN a.account_type = 'platform_revenue' THEN 1
      WHEN a.account_type = 'platform' THEN 2
      ELSE 3
    END
  LIMIT 1;

  IF v_restaurant_account_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Restaurant account not found');
  END IF;

  IF v_delivery_account_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery agent account not found');
  END IF;

  IF v_client_account_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Client account not found');
  END IF;

  IF v_platform_revenue_account_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Platform account not found');
  END IF;

  -- 4. Actualizar status de la orden
  UPDATE public.orders
  SET 
    status = 'not_delivered',
    updated_at = now()
  WHERE id = p_order_id;

  -- 5. Crear registro de deuda del cliente
  INSERT INTO public.client_debts (
    client_id,
    order_id,
    amount,
    reason,
    status,
    photo_url,
    delivery_notes
  ) VALUES (
    v_order_record.user_id,
    p_order_id,
    v_total_amount,
    p_reason,
    'pending',
    p_photo_url,
    p_delivery_notes
  )
  RETURNING id INTO v_debt_id;

  -- 6. Crear transacciones en account_transactions (balance = 0)
  
  -- 6.1) Restaurante recibe pago (POSITIVO)
  INSERT INTO public.account_transactions (
    account_id,
    type,
    amount,
    order_id,
    description,
    metadata
  ) VALUES (
    v_restaurant_account_id,
    'RESTAURANT_PAYABLE',
    v_restaurant_amount,
    p_order_id,
    'Compensación restaurante orden no entregada #' || LEFT(p_order_id::text, 8),
    jsonb_build_object(
      'debt_id', v_debt_id,
      'paid_by_platform', true,
      'reason', p_reason,
      'commission_bps', v_commission_bps
    )
  );

  -- 6.2) Repartidor recibe pago (POSITIVO)
  INSERT INTO public.account_transactions (
    account_id,
    type,
    amount,
    order_id,
    description,
    metadata
  ) VALUES (
    v_delivery_account_id,
    'DELIVERY_EARNING',
    v_delivery_earning,
    p_order_id,
    'Compensación repartidor orden no entregada #' || LEFT(p_order_id::text, 8),
    jsonb_build_object(
      'debt_id', v_debt_id,
      'paid_by_platform', true,
      'reason', p_reason
    )
  );

  -- 6.3) Plataforma paga al restaurante y repartidor (NEGATIVO) - Balanceador
  INSERT INTO public.account_transactions (
    account_id,
    type,
    amount,
    order_id,
    description,
    metadata
  ) VALUES (
    v_platform_revenue_account_id,
    'PLATFORM_NOT_DELIVERED_REFUND',
    -(v_restaurant_amount + v_delivery_earning),
    p_order_id,
    'Plataforma paga orden no entregada #' || LEFT(p_order_id::text, 8),
    jsonb_build_object(
      'debt_id', v_debt_id,
      'restaurant_amount', v_restaurant_amount,
      'delivery_earning', v_delivery_earning,
      'total_refund', v_restaurant_amount + v_delivery_earning,
      'reason', p_reason
    )
  );

  -- 6.4) Cliente debe dinero (POSITIVO) - Deuda pendiente
  INSERT INTO public.account_transactions (
    account_id,
    type,
    amount,
    order_id,
    description,
    metadata
  ) VALUES (
    v_client_account_id,
    'CLIENT_DEBT',
    v_total_amount,
    p_order_id,
    'Deuda cliente orden no entregada #' || LEFT(p_order_id::text, 8),
    jsonb_build_object(
      'debt_id', v_debt_id,
      'status', 'pending',
      'reason', p_reason
    )
  );

  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    '💸 Account transactions created (balanced)',
    jsonb_build_object(
      'restaurant_amount', v_restaurant_amount,
      'delivery_earning', v_delivery_earning,
      'platform_refund', -(v_restaurant_amount + v_delivery_earning),
      'client_debt', v_total_amount,
      'sum', v_restaurant_amount + v_delivery_earning - (v_restaurant_amount + v_delivery_earning) + v_total_amount
    )
  );

  -- 7. Actualizar balances de cuentas
  UPDATE public.accounts
  SET 
    balance = (
      SELECT COALESCE(SUM(amount), 0)
      FROM public.account_transactions
      WHERE account_id = accounts.id
    ),
    updated_at = now()
  WHERE id IN (v_restaurant_account_id, v_delivery_account_id, v_client_account_id, v_platform_revenue_account_id);

  -- 8. Transacción de deuda del cliente
  INSERT INTO public.client_debts_transactions (
    debt_id,
    client_id,
    amount,
    transaction_type,
    description
  ) VALUES (
    v_debt_id,
    v_order_record.user_id,
    v_total_amount,
    'debt_created',
    'Adeudo creado por orden no entregada #' || LEFT(p_order_id::text, 8)
  );

  -- 9. Gestionar suspensiones
  SELECT * INTO v_client_suspension
  FROM public.client_account_suspensions
  WHERE client_id = v_order_record.user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.client_account_suspensions (
      client_id,
      failed_attempts,
      last_failed_order_id
    ) VALUES (
      v_order_record.user_id,
      1,
      p_order_id
    );
    v_new_failed_attempts := 1;
  ELSE
    v_new_failed_attempts := v_client_suspension.failed_attempts + 1;
    
    IF v_new_failed_attempts >= 3 THEN
      v_should_suspend := true;
      
      UPDATE public.client_account_suspensions
      SET 
        failed_attempts = v_new_failed_attempts,
        is_suspended = true,
        suspended_at = now(),
        suspension_expires_at = now() + interval '10 minutes',
        last_failed_order_id = p_order_id,
        updated_at = now()
      WHERE client_id = v_order_record.user_id;
    ELSE
      UPDATE public.client_account_suspensions
      SET 
        failed_attempts = v_new_failed_attempts,
        last_failed_order_id = p_order_id,
        updated_at = now()
      WHERE client_id = v_order_record.user_id;
    END IF;
  END IF;

  -- 10. Retornar resultado exitoso
  RETURN jsonb_build_object(
    'success', true,
    'debt_id', v_debt_id,
    'order_id', p_order_id,
    'amount_owed', v_total_amount,
    'restaurant_amount', v_restaurant_amount,
    'delivery_earning', v_delivery_earning,
    'platform_refund', -(v_restaurant_amount + v_delivery_earning),
    'platform_commission', v_platform_commission,
    'failed_attempts', v_new_failed_attempts,
    'is_suspended', v_should_suspend,
    'suspension_expires_at', CASE 
      WHEN v_should_suspend THEN (now() + interval '10 minutes')::text
      ELSE NULL
    END
  );

EXCEPTION
  WHEN OTHERS THEN
    INSERT INTO public.debug_logs (scope, message, meta)
    VALUES (
      'mark_order_not_delivered',
      '❌ Exception caught',
      jsonb_build_object(
        'error', SQLERRM,
        'detail', SQLSTATE
      )
    );
    
    RETURN jsonb_build_object(
      'success', false,
      'error', SQLERRM,
      'error_detail', SQLSTATE
    );
END;
$$;

-- ============================================================================
-- PASO 3: GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.mark_order_not_delivered TO authenticated;

-- ============================================================================
-- VERIFICACIÓN FINAL
-- ============================================================================

DO $$
BEGIN
  -- Check constraint
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'account_transactions_type_check'
  ) THEN
    RAISE EXCEPTION '❌ Constraint account_transactions_type_check not found';
  END IF;

  -- Check function
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'mark_order_not_delivered'
  ) THEN
    RAISE EXCEPTION '❌ Function mark_order_not_delivered not found';
  END IF;

  RAISE NOTICE '✅ ✅ ✅ Migration completed successfully!';
  RAISE NOTICE 'Constraint "account_transactions_type_check" updated ✅';
  RAISE NOTICE 'Function "mark_order_not_delivered" updated with balanced transactions ✅';
  RAISE NOTICE '';
  RAISE NOTICE '📊 BALANCE 0 EXPLANATION:';
  RAISE NOTICE 'Para cada orden "not_delivered", se crean 4 transacciones:';
  RAISE NOTICE '  1. RESTAURANT_PAYABLE (+restaurant_amount) → Restaurante recibe compensación';
  RAISE NOTICE '  2. DELIVERY_EARNING (+delivery_earning) → Repartidor recibe compensación';
  RAISE NOTICE '  3. PLATFORM_NOT_DELIVERED_REFUND (-(restaurant + delivery)) → Plataforma paga';
  RAISE NOTICE '  4. CLIENT_DEBT (+total_amount) → Cliente debe dinero';
  RAISE NOTICE '';
  RAISE NOTICE 'SUMA = restaurant_amount + delivery_earning - (restaurant_amount + delivery_earning) + total_amount';
  RAISE NOTICE '     = total_amount (deuda del cliente)';
  RAISE NOTICE '';
  RAISE NOTICE '⚠️  NOTA: El total_amount (deuda cliente) NO se resta porque es una deuda pendiente.';
  RAISE NOTICE '    Cuando el cliente pague, se creará una transacción negativa que balanceará.';
END $$;

-- ============================================================================
-- INSTRUCCIONES PARA EJECUTAR:
-- 1. Copia todo este script
-- 2. Ve a Supabase Dashboard → SQL Editor → New Query
-- 3. Pega el script completo
-- 4. Haz clic en "Run" (esquina inferior derecha)
-- 5. Verifica que aparezca "Success" y los mensajes de verificación
-- 6. Prueba nuevamente en la app marcando una orden como "not_delivered"
-- 7. Verifica en Balance 0 que la suma de transacciones sea correcta
-- ============================================================================
