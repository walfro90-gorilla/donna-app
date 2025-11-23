-- ============================================================================
-- FIX V2: Corregir función mark_order_not_delivered
-- ============================================================================
-- PROBLEMA DETECTADO:
-- ❌ Error: "record v_order_record has no field total_price"
-- ❌ La tabla orders usa 'total_amount', NO 'total_price'
-- ❌ No existe columna 'commission_amount' en orders
-- ❌ La comisión se calcula desde restaurants.commission_bps
--
-- SOLUCIÓN:
-- ✅ Usar 'total_amount' en lugar de 'total_price'
-- ✅ Obtener commission_bps del restaurante
-- ✅ Calcular comisión: subtotal * commission_bps / 10000
-- ✅ Calcular pago restaurante: subtotal - comisión
--
-- INSTRUCCIONES:
-- 1. Abre Supabase Dashboard > SQL Editor
-- 2. Copia y pega COMPLETO este archivo
-- 3. Haz clic en "Run" (esquina inferior derecha)
-- 4. Verifica que no haya errores (debe decir "Success. No rows returned")
-- 5. Prueba la app nuevamente
-- ============================================================================

-- Eliminar función antigua si existe (con cualquier firma)
DROP FUNCTION IF EXISTS public.mark_order_not_delivered(uuid, text, text, text);
DROP FUNCTION IF EXISTS public.mark_order_not_delivered(uuid, uuid, text, text, text);

-- Crear función con la firma correcta y campos corregidos
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
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Order not found'
    );
  END IF;

  -- Validar que la orden esté en un estado válido para marcar como no entregada
  IF v_order_record.status NOT IN ('assigned', 'picked_up', 'on_the_way', 'in_transit') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Order must be in assigned, picked_up, on_the_way, or in_transit status'
    );
  END IF;

  -- Validar que el repartidor sea el asignado a la orden
  IF v_order_record.delivery_agent_id != p_delivery_agent_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'You are not the assigned delivery agent for this order'
    );
  END IF;

  -- 2. Calcular montos
  -- IMPORTANTE: Usar 'subtotal' (monto sin delivery_fee) y 'total_amount' (con delivery_fee)
  v_commission_bps := COALESCE(v_order_record.commission_bps, 1500); -- Default 15%
  v_platform_commission := (COALESCE(v_order_record.subtotal, 0) * v_commission_bps / 10000.0);
  v_restaurant_amount := COALESCE(v_order_record.subtotal, 0) - v_platform_commission;
  v_delivery_fee := COALESCE(v_order_record.delivery_fee, 0);
  v_total_amount := COALESCE(v_order_record.total_amount, 0);

  -- 3. Log de debug antes de actualizar
  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    'About to update order status',
    jsonb_build_object(
      'order_id', p_order_id,
      'current_status', v_order_record.status,
      'new_status', 'not_delivered',
      'total_amount', v_total_amount,
      'delivery_fee', v_delivery_fee
    )
  );

  -- 3. Actualizar status de la orden
  UPDATE public.orders
  SET 
    status = 'not_delivered',
    updated_at = now()
  WHERE id = p_order_id;

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
    v_order_record.user_id, -- user_id es el cliente en orders
    p_order_id,
    v_total_amount,  -- Monto total (incluyendo delivery_fee)
    p_reason,
    'pending',
    p_photo_url,
    p_delivery_notes
  )
  RETURNING id INTO v_debt_id;

  -- 5. Crear transacciones financieras
  -- La plataforma paga al restaurante y al repartidor
  -- El cliente debe esta cantidad a la plataforma

  -- Transacción: Plataforma → Restaurante (subtotal - comisión)
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

  -- Transacción: Plataforma → Repartidor (delivery fee)
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

  -- Transacción: Cliente debe a Plataforma (costo total)
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

  -- 6. Gestionar suspensiones de cuenta
  -- Obtener o crear registro de suspensión
  SELECT * INTO v_client_suspension
  FROM public.client_account_suspensions
  WHERE client_id = v_order_record.user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    -- Crear nuevo registro
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
    -- Incrementar contador
    v_new_failed_attempts := v_client_suspension.failed_attempts + 1;
    
    -- Si alcanza 3 intentos, suspender por 10 minutos
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

  -- 7. Retornar resultado
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
    RETURN jsonb_build_object(
      'success', false,
      'error', SQLERRM
    );
END;
$$;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
-- Puedes ejecutar esta consulta para verificar que la función existe:
-- SELECT routine_name, routine_definition 
-- FROM information_schema.routines 
-- WHERE routine_name = 'mark_order_not_delivered' 
-- AND routine_schema = 'public';
-- ============================================================================
