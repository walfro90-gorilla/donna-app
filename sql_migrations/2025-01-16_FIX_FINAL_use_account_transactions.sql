-- ============================================================================
-- FIX FINAL: RPC mark_order_not_delivered usando account_transactions
-- ============================================================================
-- Date: 2025-01-16
-- Purpose: 
--   Reemplazar financial_transactions por account_transactions (tabla real)
--   Corregir todos los errores de nombres de columnas y estructura
-- ============================================================================
-- ❌ PROBLEMA ENCONTRADO:
--   Error: "relation public.financial_transactions does not exist"
-- 
-- ✅ SOLUCIÓN:
--   El schema real usa 'account_transactions', NO 'financial_transactions'
--   Además, account_transactions tiene estructura diferente:
--   - Usa 'account_id' en lugar de 'user_id'
--   - Usa 'type' en lugar de 'transaction_type'
--   - NO tiene campo 'balance_after' (se calcula con SUM)
-- ============================================================================

-- ============================================================================
-- PASO 1: Asegurar que 'not_delivered' está en el constraint
-- ============================================================================

DO $$
BEGIN
  -- Drop existing constraints
  ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
  ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check_final;
  
  -- Add constraint with 'not_delivered'
  ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check_final
  CHECK (
    status = ANY (ARRAY[
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
    ])
  );
  
  RAISE NOTICE '✅ Constraint orders_status_check_final updated';
END $$;

-- ============================================================================
-- PASO 2: Asegurar que existen las tablas necesarias
-- ============================================================================

-- Tabla: client_debts
CREATE TABLE IF NOT EXISTS public.client_debts (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  client_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  amount numeric(10,2) NOT NULL CHECK (amount > 0),
  reason text NOT NULL DEFAULT 'not_delivered' CHECK (reason IN (
    'not_delivered', 'client_no_show', 'fake_address', 'other'
  )),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'paid', 'forgiven', 'disputed'
  )),
  photo_url text,
  delivery_notes text,
  dispute_reason text,
  dispute_photo_url text,
  dispute_created_at timestamptz,
  dispute_resolved_at timestamptz,
  dispute_resolved_by uuid REFERENCES public.users(id),
  dispute_resolution_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz,
  forgiven_at timestamptz,
  forgiven_by uuid REFERENCES public.users(id),
  metadata jsonb DEFAULT '{}'::jsonb
);

-- Tabla: client_account_suspensions
CREATE TABLE IF NOT EXISTS public.client_account_suspensions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  client_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  failed_attempts int NOT NULL DEFAULT 0,
  is_suspended boolean DEFAULT false,
  suspended_at timestamptz,
  suspension_expires_at timestamptz,
  last_failed_order_id uuid REFERENCES public.orders(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Tabla: client_debts_transactions
CREATE TABLE IF NOT EXISTS public.client_debts_transactions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  debt_id uuid NOT NULL REFERENCES public.client_debts(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  amount numeric(10,2) NOT NULL,
  transaction_type text NOT NULL CHECK (transaction_type IN (
    'debt_created', 'payment', 'forgiven', 'dispute_created', 'dispute_resolved'
  )),
  description text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_client_debts_client ON public.client_debts(client_id);
CREATE INDEX IF NOT EXISTS idx_client_debts_order ON public.client_debts(order_id);
CREATE INDEX IF NOT EXISTS idx_client_debts_status ON public.client_debts(status);

-- ============================================================================
-- PASO 3: RECREAR RPC mark_order_not_delivered (VERSIÓN CORRECTA)
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
  v_platform_commission numeric;
  v_commission_bps integer;
  v_client_suspension RECORD;
  v_new_failed_attempts int;
  v_should_suspend boolean := false;
  v_restaurant_account_id uuid;
  v_delivery_account_id uuid;
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

  -- 2. Calcular montos (usando campos correctos del schema)
  v_commission_bps := COALESCE(v_order_record.commission_bps, 1500);
  v_platform_commission := (COALESCE(v_order_record.subtotal, 0) * v_commission_bps / 10000.0);
  v_restaurant_amount := COALESCE(v_order_record.subtotal, 0) - v_platform_commission;
  v_delivery_fee := COALESCE(v_order_record.delivery_fee, 0);
  v_total_amount := COALESCE(v_order_record.total_amount, 0);

  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    '💰 Amounts calculated',
    jsonb_build_object(
      'total_amount', v_total_amount,
      'subtotal', v_order_record.subtotal,
      'restaurant_amount', v_restaurant_amount,
      'delivery_fee', v_delivery_fee,
      'platform_commission', v_platform_commission,
      'commission_bps', v_commission_bps
    )
  );

  -- 3. Obtener account_id del restaurante
  SELECT a.id INTO v_restaurant_account_id
  FROM public.accounts a
  WHERE a.user_id = v_order_record.restaurant_owner_id
    AND a.account_type = 'restaurant'
  LIMIT 1;

  -- 4. Obtener account_id del repartidor
  SELECT a.id INTO v_delivery_account_id
  FROM public.accounts a
  WHERE a.user_id = p_delivery_agent_id
    AND a.account_type = 'delivery_agent'
  LIMIT 1;

  IF v_restaurant_account_id IS NULL THEN
    INSERT INTO public.debug_logs (scope, message, meta)
    VALUES ('mark_order_not_delivered', '❌ Restaurant account not found', 
            jsonb_build_object('restaurant_owner_id', v_order_record.restaurant_owner_id));
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Restaurant account not found'
    );
  END IF;

  IF v_delivery_account_id IS NULL THEN
    INSERT INTO public.debug_logs (scope, message, meta)
    VALUES ('mark_order_not_delivered', '❌ Delivery agent account not found', 
            jsonb_build_object('delivery_agent_id', p_delivery_agent_id));
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Delivery agent account not found'
    );
  END IF;

  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    '✅ Accounts found',
    jsonb_build_object(
      'restaurant_account_id', v_restaurant_account_id,
      'delivery_account_id', v_delivery_account_id
    )
  );

  -- 5. Actualizar status de la orden
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

  -- 6. Crear registro de deuda del cliente
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

  -- 7. Crear transacciones en account_transactions (usando estructura correcta)
  -- Transacción: Plataforma → Restaurante
  INSERT INTO public.account_transactions (
    account_id,
    type,
    amount,
    order_id,
    description,
    metadata
  ) VALUES (
    v_restaurant_account_id,
    'ORDER_REVENUE',
    v_restaurant_amount,
    p_order_id,
    'Pago por orden #' || p_order_id || ' (no entregada - pagado por plataforma)',
    jsonb_build_object(
      'debt_id', v_debt_id,
      'paid_by_platform', true,
      'reason', 'not_delivered',
      'commission_bps', v_commission_bps,
      'platform_commission', v_platform_commission
    )
  );

  -- Transacción: Plataforma → Repartidor
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
    v_delivery_fee,
    p_order_id,
    'Pago por entrega #' || p_order_id || ' (intento fallido - pagado por plataforma)',
    jsonb_build_object(
      'debt_id', v_debt_id,
      'paid_by_platform', true,
      'reason', 'not_delivered'
    )
  );

  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'mark_order_not_delivered',
    '💸 Account transactions created',
    jsonb_build_object(
      'restaurant_amount', v_restaurant_amount,
      'delivery_fee', v_delivery_fee
    )
  );

  -- 8. Actualizar balances de cuentas
  UPDATE public.accounts
  SET 
    balance = (
      SELECT COALESCE(SUM(amount), 0)
      FROM public.account_transactions
      WHERE account_id = accounts.id
    ),
    updated_at = now()
  WHERE id IN (v_restaurant_account_id, v_delivery_account_id);

  -- 9. Transacción de deuda del cliente
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

  -- 10. Gestionar suspensiones
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

  -- 11. Retornar resultado exitoso
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
-- PASO 4: GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.mark_order_not_delivered TO authenticated;

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

  -- Check tables
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'client_debts'
  ) THEN
    RAISE EXCEPTION '❌ Table client_debts not found';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'client_account_suspensions'
  ) THEN
    RAISE EXCEPTION '❌ Table client_account_suspensions not found';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'client_debts_transactions'
  ) THEN
    RAISE EXCEPTION '❌ Table client_debts_transactions not found';
  END IF;

  RAISE NOTICE '✅ ✅ ✅ Migration completed successfully!';
  RAISE NOTICE 'Constraint "orders_status_check_final" ✅';
  RAISE NOTICE 'Function "mark_order_not_delivered" ✅';
  RAISE NOTICE 'Tables created: client_debts, client_account_suspensions, client_debts_transactions ✅';
END $$;

-- ============================================================================
-- SIGUIENTE PASO:
-- 1. Ejecuta este script en Supabase SQL Editor
-- 2. Verifica que diga "Success" y "Migration completed successfully!"
-- 3. Prueba nuevamente en la app
-- 4. Si sigue fallando, revisa los logs con:
--    SELECT * FROM debug_logs 
--    WHERE scope = 'mark_order_not_delivered' 
--    ORDER BY ts DESC 
--    LIMIT 20;
-- ============================================================================
