-- ============================================================================
-- MIGRATION FINAL: Fix completo para "not_delivered" status
-- ============================================================================
-- Date: 2025-01-16
-- Purpose: 
--   1. Agregar 'not_delivered' al constraint de status en orders
--   2. Actualizar función mark_order_not_delivered con logs y campos correctos
-- ============================================================================
-- INSTRUCCIONES:
-- 1. Abre Supabase Dashboard > SQL Editor
-- 2. Copia y pega COMPLETO este archivo
-- 3. Haz clic en "Run" (esquina inferior derecha)
-- 4. Verifica que diga "Success. No rows returned"
-- 5. Prueba la app nuevamente
-- ============================================================================

-- ============================================================================
-- PARTE 1: Agregar 'not_delivered' al constraint de orders.status
-- ============================================================================

-- Drop existing constraint
ALTER TABLE public.orders 
  DROP CONSTRAINT IF EXISTS orders_status_check_final;

-- Add new constraint with 'not_delivered'
ALTER TABLE public.orders 
  ADD CONSTRAINT orders_status_check_final 
  CHECK (
    status = ANY (
      ARRAY[
        'pending'::text, 
        'confirmed'::text, 
        'preparing'::text, 
        'in_preparation'::text, 
        'ready_for_pickup'::text, 
        'assigned'::text, 
        'picked_up'::text, 
        'on_the_way'::text, 
        'in_transit'::text, 
        'delivered'::text, 
        'cancelled'::text, 
        'canceled'::text,
        'not_delivered'::text  -- ✅ NEW STATUS
      ]
    )
  );

-- Verify constraint
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 
    FROM pg_constraint 
    WHERE conname = 'orders_status_check_final'
  ) THEN
    RAISE NOTICE '✅ Constraint orders_status_check_final updated successfully';
  ELSE
    RAISE EXCEPTION '❌ Failed to update constraint';
  END IF;
END $$;

-- ============================================================================
-- PARTE 2: Actualizar función mark_order_not_delivered
-- ============================================================================

-- Drop old function versions
DROP FUNCTION IF EXISTS public.mark_order_not_delivered(uuid, text, text, text);
DROP FUNCTION IF EXISTS public.mark_order_not_delivered(uuid, uuid, text, text, text);

-- Create new function with correct fields and debug logs
CREATE OR REPLACE FUNCTION public.mark_order_not_delivered(
  p_order_id uuid,
  p_delivery_agent_id uuid,
  p_reason text DEFAULT 'not_delivered',
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
  v_platform_commission numeric;
  v_commission_bps integer;
  v_client_suspension RECORD;
  v_new_failed_attempts int;
  v_should_suspend boolean := false;
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
    INSERT INTO public.debug_logs (scope, message, meta)
    VALUES ('mark_order_not_delivered', '❌ Order not found', jsonb_build_object('order_id', p_order_id));
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Order not found'
    );
  END IF;

  -- Log order info
  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    '📦 Order found',
    jsonb_build_object(
      'order_id', p_order_id,
      'current_status', v_order_record.status,
      'delivery_agent_id', v_order_record.delivery_agent_id,
      'total_amount', v_order_record.total_amount,
      'subtotal', v_order_record.subtotal,
      'delivery_fee', v_order_record.delivery_fee
    )
  );

  -- Validar estado
  IF v_order_record.status NOT IN ('assigned', 'picked_up', 'on_the_way', 'in_transit') THEN
    INSERT INTO public.debug_logs (scope, message, meta)
    VALUES (
      'mark_order_not_delivered', 
      '❌ Invalid status', 
      jsonb_build_object('current_status', v_order_record.status)
    );
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Order must be in assigned, picked_up, on_the_way, or in_transit status'
    );
  END IF;

  -- Validar repartidor
  IF v_order_record.delivery_agent_id != p_delivery_agent_id THEN
    INSERT INTO public.debug_logs (scope, message, meta)
    VALUES (
      'mark_order_not_delivered', 
      '❌ Wrong delivery agent', 
      jsonb_build_object(
        'expected', v_order_record.delivery_agent_id,
        'received', p_delivery_agent_id
      )
    );
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You are not the assigned delivery agent for this order'
    );
  END IF;

  -- 2. Calcular montos
  v_commission_bps := COALESCE(v_order_record.commission_bps, 1500);
  v_platform_commission := (COALESCE(v_order_record.subtotal, 0) * v_commission_bps / 10000.0);
  v_restaurant_amount := COALESCE(v_order_record.subtotal, 0) - v_platform_commission;
  v_delivery_fee := COALESCE(v_order_record.delivery_fee, 0);
  v_total_amount := COALESCE(v_order_record.total_amount, 0);

  -- Log amounts
  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    '💰 Amounts calculated',
    jsonb_build_object(
      'total_amount', v_total_amount,
      'restaurant_amount', v_restaurant_amount,
      'delivery_fee', v_delivery_fee,
      'platform_commission', v_platform_commission,
      'commission_bps', v_commission_bps
    )
  );

  -- 3. Actualizar status de la orden
  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    '📝 About to update order status to not_delivered',
    jsonb_build_object('order_id', p_order_id)
  );

  UPDATE public.orders
  SET 
    status = 'not_delivered',
    updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    '✅ Order status updated to not_delivered',
    jsonb_build_object('order_id', p_order_id)
  );

  -- 4. Crear registro de deuda del cliente
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

  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    '💳 Client debt created',
    jsonb_build_object('debt_id', v_debt_id, 'amount', v_total_amount)
  );

  -- 5. Crear transacciones financieras
  -- Transacción: Plataforma → Restaurante
  INSERT INTO public.financial_transactions (
    user_id,
    order_id,
    transaction_type,
    amount,
    balance_after,
    description,
    metadata
  )
  SELECT
    v_order_record.restaurant_owner_id,
    p_order_id,
    'order_completed',
    v_restaurant_amount,
    COALESCE(
      (SELECT balance_after FROM public.financial_transactions 
       WHERE user_id = v_order_record.restaurant_owner_id 
       ORDER BY created_at DESC LIMIT 1), 
      0
    ) + v_restaurant_amount,
    'Pago por orden #' || p_order_id || ' (no entregada - pagado por plataforma)',
    jsonb_build_object(
      'debt_id', v_debt_id,
      'paid_by_platform', true,
      'reason', 'not_delivered',
      'commission_bps', v_commission_bps,
      'platform_commission', v_platform_commission
    );

  -- Transacción: Plataforma → Repartidor
  INSERT INTO public.financial_transactions (
    user_id,
    order_id,
    transaction_type,
    amount,
    balance_after,
    description,
    metadata
  )
  SELECT
    p_delivery_agent_id,
    p_order_id,
    'delivery_completed',
    v_delivery_fee,
    COALESCE(
      (SELECT balance_after FROM public.financial_transactions 
       WHERE user_id = p_delivery_agent_id 
       ORDER BY created_at DESC LIMIT 1), 
      0
    ) + v_delivery_fee,
    'Pago por entrega #' || p_order_id || ' (intento fallido - pagado por plataforma)',
    jsonb_build_object(
      'debt_id', v_debt_id,
      'paid_by_platform', true,
      'reason', 'not_delivered'
    );

  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    '💸 Financial transactions created',
    jsonb_build_object(
      'restaurant_amount', v_restaurant_amount,
      'delivery_fee', v_delivery_fee
    )
  );

  -- Transacción: Cliente debe a Plataforma
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
    'Adeudo creado por orden no entregada #' || p_order_id
  );

  -- 6. Gestionar suspensiones
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

  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    '🚫 Suspension check complete',
    jsonb_build_object(
      'failed_attempts', v_new_failed_attempts,
      'is_suspended', v_should_suspend
    )
  );

  -- 7. Retornar resultado exitoso
  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    '✅ Function completed successfully',
    jsonb_build_object('debt_id', v_debt_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'debt_id', v_debt_id,
    'order_id', p_order_id,
    'amount_owed', v_total_amount,
    'restaurant_amount', v_restaurant_amount,
    'delivery_fee', v_delivery_fee,
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
-- VERIFICACIÓN FINAL
-- ============================================================================
DO $$
BEGIN
  -- Check constraint
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'orders_status_check_final'
  ) THEN
    RAISE EXCEPTION '❌ Constraint orders_status_check_final not found';
  END IF;

  -- Check function
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'mark_order_not_delivered'
  ) THEN
    RAISE EXCEPTION '❌ Function mark_order_not_delivered not found';
  END IF;

  RAISE NOTICE '✅ ✅ ✅ Migration completed successfully!';
  RAISE NOTICE 'Constraint "orders_status_check_final" updated';
  RAISE NOTICE 'Function "mark_order_not_delivered" created with debug logs';
END $$;

-- ============================================================================
-- SIGUIENTE PASO:
-- Después de ejecutar este script, prueba nuevamente en la app.
-- Si sigue fallando, revisa los logs en Supabase con:
--
-- SELECT * FROM debug_logs 
-- WHERE scope = 'mark_order_not_delivered' 
-- ORDER BY ts DESC 
-- LIMIT 20;
-- ============================================================================
