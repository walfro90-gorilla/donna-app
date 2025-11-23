-- ============================================================================
-- SISTEMA DE ÓRDENES NO ENTREGADAS (NOT DELIVERED)
-- ============================================================================
-- Propósito: Permitir a repartidores marcar órdenes como no entregadas
--           cuando el cliente no está disponible o es una dirección falsa.
--           El sistema carga automáticamente el costo al cliente y mantiene
--           el balance en cero mediante transacciones contables correctas.
-- 
-- Características:
-- ✅ Nuevo status 'not_delivered'
-- ✅ Sistema de adeudos de clientes con evidencia fotográfica
-- ✅ Sistema de disputas (cliente puede disputar el adeudo)
-- ✅ Sistema de perdón de deudas por admin
-- ✅ Bloqueo temporal de cuenta (10 min) después de 3 intentos fallidos
-- ✅ Transacciones automáticas para mantener balance 0
-- ============================================================================

-- ============================================================================
-- PASO 1: AGREGAR NUEVO STATUS 'not_delivered' A ÓRDENES
-- ============================================================================

-- Verificar si ya existe el status
DO $$ 
BEGIN
  -- Agregar 'not_delivered' al check constraint de orders.status
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'orders_status_check'
  ) THEN
    ALTER TABLE public.orders
    ADD CONSTRAINT orders_status_check 
    CHECK (status IN (
      'pending', 
      'confirmed', 
      'preparing', 
      'in_preparation', 
      'ready_for_pickup', 
      'assigned', 
      'picked_up', 
      'on_the_way', 
      'in_transit', 
      'delivered', 
      'cancelled', 
      'canceled',
      'not_delivered'  -- NUEVO STATUS
    ));
  ELSE
    -- Drop y recrear constraint
    ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
    ALTER TABLE public.orders
    ADD CONSTRAINT orders_status_check 
    CHECK (status IN (
      'pending', 
      'confirmed', 
      'preparing', 
      'in_preparation', 
      'ready_for_pickup', 
      'assigned', 
      'picked_up', 
      'on_the_way', 
      'in_transit', 
      'delivered', 
      'cancelled', 
      'canceled',
      'not_delivered'  -- NUEVO STATUS
    ));
  END IF;
END $$;

-- ============================================================================
-- PASO 2: CREAR TABLA client_debts (Adeudos de Clientes)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.client_debts (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Relaciones
  client_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  
  -- Montos
  amount numeric(10,2) NOT NULL CHECK (amount > 0),
  
  -- Razón del adeudo
  reason text NOT NULL DEFAULT 'not_delivered' CHECK (reason IN (
    'not_delivered',    -- Cliente no disponible
    'client_no_show',   -- Cliente no apareció
    'fake_address',     -- Dirección falsa o incorrecta
    'other'             -- Otra razón
  )),
  
  -- Estado del adeudo
  status text NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending',      -- Pendiente de pago
    'paid',         -- Pagado
    'forgiven',     -- Perdonado por admin
    'disputed'      -- En disputa
  )),
  
  -- Evidencia fotográfica
  photo_url text,           -- URL de la foto de evidencia (lugar, dirección, etc.)
  delivery_notes text,      -- Notas del repartidor
  
  -- Sistema de disputas
  dispute_reason text,                  -- Razón de la disputa del cliente
  dispute_photo_url text,               -- Foto de evidencia del cliente
  dispute_created_at timestamptz,       -- Fecha de creación de la disputa
  dispute_resolved_at timestamptz,      -- Fecha de resolución de la disputa
  dispute_resolved_by uuid REFERENCES public.users(id), -- Admin que resolvió
  dispute_resolution_notes text,        -- Notas de la resolución
  
  -- Metadatos
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz,        -- Fecha de pago
  forgiven_at timestamptz,    -- Fecha de perdón
  forgiven_by uuid REFERENCES public.users(id), -- Admin que perdonó
  
  -- Información adicional
  metadata jsonb DEFAULT '{}'::jsonb
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_client_debts_client ON public.client_debts(client_id);
CREATE INDEX IF NOT EXISTS idx_client_debts_order ON public.client_debts(order_id);
CREATE INDEX IF NOT EXISTS idx_client_debts_status ON public.client_debts(status);
CREATE INDEX IF NOT EXISTS idx_client_debts_created ON public.client_debts(created_at DESC);

-- Trigger para updated_at
CREATE OR REPLACE FUNCTION update_client_debts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_client_debts_updated_at ON public.client_debts;
CREATE TRIGGER trigger_client_debts_updated_at
  BEFORE UPDATE ON public.client_debts
  FOR EACH ROW
  EXECUTE FUNCTION update_client_debts_updated_at();

-- ============================================================================
-- PASO 3: CREAR TABLA client_account_suspensions (Suspensiones Temporales)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.client_account_suspensions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  client_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  
  -- Contador de intentos fallidos
  failed_attempts int NOT NULL DEFAULT 0,
  
  -- Suspensión
  is_suspended boolean DEFAULT false,
  suspended_at timestamptz,
  suspension_expires_at timestamptz,  -- 10 minutos desde suspended_at
  
  -- Historial
  last_failed_order_id uuid REFERENCES public.orders(id),
  
  -- Metadata
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_suspensions_client ON public.client_account_suspensions(client_id);
CREATE INDEX IF NOT EXISTS idx_suspensions_active ON public.client_account_suspensions(is_suspended, suspension_expires_at);

-- Trigger para updated_at
DROP TRIGGER IF EXISTS trigger_suspensions_updated_at ON public.client_account_suspensions;
CREATE TRIGGER trigger_suspensions_updated_at
  BEFORE UPDATE ON public.client_account_suspensions
  FOR EACH ROW
  EXECUTE FUNCTION update_client_debts_updated_at();

-- ============================================================================
-- PASO 4: RPC - mark_order_not_delivered
-- ============================================================================
-- Función principal que marca una orden como no entregada y crea todas
-- las transacciones necesarias para mantener el balance en 0

CREATE OR REPLACE FUNCTION public.mark_order_not_delivered(
  p_order_id uuid,
  p_delivery_agent_id uuid,
  p_photo_url text DEFAULT NULL,
  p_delivery_notes text DEFAULT NULL,
  p_reason text DEFAULT 'not_delivered'
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
  v_client_suspension RECORD;
  v_new_failed_attempts int;
  v_should_suspend boolean := false;
BEGIN
  -- 1. Obtener información de la orden
  SELECT 
    o.*,
    r.user_id as restaurant_owner_id
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
  v_total_amount := COALESCE(v_order_record.total_price, 0);
  v_restaurant_amount := COALESCE(v_order_record.total_price, 0) - COALESCE(v_order_record.commission_amount, 0);
  v_delivery_fee := COALESCE(v_order_record.delivery_fee, 0);
  v_platform_commission := COALESCE(v_order_record.commission_amount, 0);

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
    v_order_record.client_id,
    p_order_id,
    v_total_amount + v_delivery_fee,  -- Monto total + delivery fee
    p_reason,
    'pending',
    p_photo_url,
    p_delivery_notes
  )
  RETURNING id INTO v_debt_id;

  -- 5. Crear transacciones financieras
  -- La plataforma paga al restaurante y al repartidor
  -- El cliente debe esta cantidad a la plataforma

  -- Transacción: Plataforma → Restaurante (monto del pedido - comisión)
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
      'reason', 'not_delivered'
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
    v_order_record.client_id,
    v_total_amount + v_delivery_fee,
    'debt_created',
    'Adeudo creado por orden no entregada #' || p_order_id
  );

  -- 6. Gestionar suspensiones de cuenta
  -- Obtener o crear registro de suspensión
  SELECT * INTO v_client_suspension
  FROM public.client_account_suspensions
  WHERE client_id = v_order_record.client_id
  FOR UPDATE;

  IF NOT FOUND THEN
    -- Crear nuevo registro
    INSERT INTO public.client_account_suspensions (
      client_id,
      failed_attempts,
      last_failed_order_id
    ) VALUES (
      v_order_record.client_id,
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
      WHERE client_id = v_order_record.client_id;
    ELSE
      UPDATE public.client_account_suspensions
      SET 
        failed_attempts = v_new_failed_attempts,
        last_failed_order_id = p_order_id,
        updated_at = now()
      WHERE client_id = v_order_record.client_id;
    END IF;
  END IF;

  -- 7. Retornar resultado
  RETURN jsonb_build_object(
    'success', true,
    'debt_id', v_debt_id,
    'order_id', p_order_id,
    'amount_owed', v_total_amount + v_delivery_fee,
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
-- PASO 5: TABLA client_debts_transactions (Historial de transacciones de deudas)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.client_debts_transactions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  debt_id uuid NOT NULL REFERENCES public.client_debts(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  
  amount numeric(10,2) NOT NULL,
  transaction_type text NOT NULL CHECK (transaction_type IN (
    'debt_created',
    'payment',
    'forgiven',
    'dispute_created',
    'dispute_resolved'
  )),
  
  description text,
  metadata jsonb DEFAULT '{}'::jsonb,
  
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_debt_transactions_debt ON public.client_debts_transactions(debt_id);
CREATE INDEX IF NOT EXISTS idx_debt_transactions_client ON public.client_debts_transactions(client_id);

-- ============================================================================
-- PASO 6: RPC - dispute_debt (Cliente disputa el adeudo)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.dispute_debt(
  p_debt_id uuid,
  p_client_id uuid,
  p_dispute_reason text,
  p_dispute_photo_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_debt RECORD;
BEGIN
  -- Obtener la deuda
  SELECT * INTO v_debt
  FROM public.client_debts
  WHERE id = p_debt_id AND client_id = p_client_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Debt not found or you are not authorized'
    );
  END IF;

  -- Validar que esté en estado pending
  IF v_debt.status != 'pending' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Debt must be in pending status to dispute'
    );
  END IF;

  -- Actualizar deuda con información de disputa
  UPDATE public.client_debts
  SET
    status = 'disputed',
    dispute_reason = p_dispute_reason,
    dispute_photo_url = p_dispute_photo_url,
    dispute_created_at = now(),
    updated_at = now()
  WHERE id = p_debt_id;

  -- Crear transacción de disputa
  INSERT INTO public.client_debts_transactions (
    debt_id,
    client_id,
    amount,
    transaction_type,
    description,
    metadata
  ) VALUES (
    p_debt_id,
    p_client_id,
    0,
    'dispute_created',
    'Cliente disputó el adeudo',
    jsonb_build_object(
      'dispute_reason', p_dispute_reason,
      'dispute_photo_url', p_dispute_photo_url
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'debt_id', p_debt_id,
    'status', 'disputed'
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
-- PASO 7: RPC - resolve_dispute (Admin resuelve disputa)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.resolve_dispute(
  p_debt_id uuid,
  p_admin_id uuid,
  p_resolution text,  -- 'forgive' o 'uphold' (mantener deuda)
  p_resolution_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_debt RECORD;
  v_admin_role text;
BEGIN
  -- Verificar que el usuario sea admin
  SELECT role INTO v_admin_role
  FROM public.users
  WHERE id = p_admin_id;

  IF v_admin_role != 'admin' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only admins can resolve disputes'
    );
  END IF;

  -- Obtener la deuda
  SELECT * INTO v_debt
  FROM public.client_debts
  WHERE id = p_debt_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Debt not found'
    );
  END IF;

  -- Validar que esté en disputa
  IF v_debt.status != 'disputed' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Debt must be in disputed status'
    );
  END IF;

  -- Resolver la disputa
  IF p_resolution = 'forgive' THEN
    -- Perdonar la deuda
    UPDATE public.client_debts
    SET
      status = 'forgiven',
      forgiven_at = now(),
      forgiven_by = p_admin_id,
      dispute_resolved_at = now(),
      dispute_resolved_by = p_admin_id,
      dispute_resolution_notes = p_resolution_notes,
      updated_at = now()
    WHERE id = p_debt_id;

    -- Resetear contador de intentos fallidos
    UPDATE public.client_account_suspensions
    SET
      failed_attempts = 0,
      is_suspended = false,
      suspended_at = NULL,
      suspension_expires_at = NULL
    WHERE client_id = v_debt.client_id;

  ELSIF p_resolution = 'uphold' THEN
    -- Mantener la deuda
    UPDATE public.client_debts
    SET
      status = 'pending',
      dispute_resolved_at = now(),
      dispute_resolved_by = p_admin_id,
      dispute_resolution_notes = p_resolution_notes,
      updated_at = now()
    WHERE id = p_debt_id;
  ELSE
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Invalid resolution. Must be "forgive" or "uphold"'
    );
  END IF;

  -- Crear transacción de resolución
  INSERT INTO public.client_debts_transactions (
    debt_id,
    client_id,
    amount,
    transaction_type,
    description,
    metadata
  ) VALUES (
    p_debt_id,
    v_debt.client_id,
    0,
    'dispute_resolved',
    'Admin resolvió la disputa: ' || p_resolution,
    jsonb_build_object(
      'resolution', p_resolution,
      'resolved_by', p_admin_id,
      'resolution_notes', p_resolution_notes
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'debt_id', p_debt_id,
    'resolution', p_resolution,
    'new_status', CASE WHEN p_resolution = 'forgive' THEN 'forgiven' ELSE 'pending' END
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
-- PASO 8: RPC - forgive_debt (Admin perdona deuda sin disputa)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.forgive_debt(
  p_debt_id uuid,
  p_admin_id uuid,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_debt RECORD;
  v_admin_role text;
BEGIN
  -- Verificar que el usuario sea admin
  SELECT role INTO v_admin_role
  FROM public.users
  WHERE id = p_admin_id;

  IF v_admin_role != 'admin' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Only admins can forgive debts'
    );
  END IF;

  -- Obtener la deuda
  SELECT * INTO v_debt
  FROM public.client_debts
  WHERE id = p_debt_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Debt not found'
    );
  END IF;

  -- Validar que esté pendiente
  IF v_debt.status NOT IN ('pending', 'disputed') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Debt must be in pending or disputed status'
    );
  END IF;

  -- Perdonar la deuda
  UPDATE public.client_debts
  SET
    status = 'forgiven',
    forgiven_at = now(),
    forgiven_by = p_admin_id,
    dispute_resolution_notes = p_notes,
    updated_at = now()
  WHERE id = p_debt_id;

  -- Resetear contador de intentos fallidos
  UPDATE public.client_account_suspensions
  SET
    failed_attempts = 0,
    is_suspended = false,
    suspended_at = NULL,
    suspension_expires_at = NULL
  WHERE client_id = v_debt.client_id;

  -- Crear transacción
  INSERT INTO public.client_debts_transactions (
    debt_id,
    client_id,
    amount,
    transaction_type,
    description,
    metadata
  ) VALUES (
    p_debt_id,
    v_debt.client_id,
    v_debt.amount,
    'forgiven',
    'Admin perdonó la deuda',
    jsonb_build_object(
      'forgiven_by', p_admin_id,
      'notes', p_notes
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'debt_id', p_debt_id,
    'status', 'forgiven'
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
-- PASO 9: RPC - check_client_suspension (Verificar si cliente está suspendido)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_client_suspension(
  p_client_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_suspension RECORD;
  v_is_suspended boolean := false;
  v_pending_debts numeric := 0;
BEGIN
  -- Obtener registro de suspensión
  SELECT * INTO v_suspension
  FROM public.client_account_suspensions
  WHERE client_id = p_client_id;

  IF FOUND THEN
    -- Si está suspendido, verificar si ya expiró
    IF v_suspension.is_suspended THEN
      IF v_suspension.suspension_expires_at < now() THEN
        -- La suspensión expiró, reactivar cuenta
        UPDATE public.client_account_suspensions
        SET
          is_suspended = false,
          suspended_at = NULL,
          suspension_expires_at = NULL,
          updated_at = now()
        WHERE client_id = p_client_id;
        
        v_is_suspended := false;
      ELSE
        v_is_suspended := true;
      END IF;
    END IF;
  END IF;

  -- Calcular deudas pendientes
  SELECT COALESCE(SUM(amount), 0) INTO v_pending_debts
  FROM public.client_debts
  WHERE client_id = p_client_id AND status = 'pending';

  RETURN jsonb_build_object(
    'is_suspended', v_is_suspended,
    'suspension_expires_at', v_suspension.suspension_expires_at,
    'failed_attempts', COALESCE(v_suspension.failed_attempts, 0),
    'pending_debts', v_pending_debts,
    'can_order', NOT v_is_suspended AND v_pending_debts = 0
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
-- PASO 10: RPC - get_client_debts (Obtener deudas de un cliente)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_client_debts(
  p_client_id uuid
)
RETURNS TABLE (
  debt_id uuid,
  order_id uuid,
  amount numeric,
  reason text,
  status text,
  photo_url text,
  delivery_notes text,
  dispute_reason text,
  dispute_photo_url text,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    cd.id,
    cd.order_id,
    cd.amount,
    cd.reason,
    cd.status,
    cd.photo_url,
    cd.delivery_notes,
    cd.dispute_reason,
    cd.dispute_photo_url,
    cd.created_at,
    cd.updated_at
  FROM public.client_debts cd
  WHERE cd.client_id = p_client_id
  ORDER BY cd.created_at DESC;
END;
$$;

-- ============================================================================
-- PASO 11: POLÍTICAS RLS (Row Level Security)
-- ============================================================================

-- Habilitar RLS
ALTER TABLE public.client_debts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_account_suspensions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_debts_transactions ENABLE ROW LEVEL SECURITY;

-- Políticas para client_debts
DROP POLICY IF EXISTS client_debts_select_own ON public.client_debts;
CREATE POLICY client_debts_select_own ON public.client_debts
  FOR SELECT
  USING (
    client_id = auth.uid() OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

DROP POLICY IF EXISTS client_debts_admin_all ON public.client_debts;
CREATE POLICY client_debts_admin_all ON public.client_debts
  FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- Políticas para client_account_suspensions
DROP POLICY IF EXISTS suspensions_select_own ON public.client_account_suspensions;
CREATE POLICY suspensions_select_own ON public.client_account_suspensions
  FOR SELECT
  USING (
    client_id = auth.uid() OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

DROP POLICY IF EXISTS suspensions_admin_all ON public.client_account_suspensions;
CREATE POLICY suspensions_admin_all ON public.client_account_suspensions
  FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- Políticas para client_debts_transactions
DROP POLICY IF EXISTS debt_transactions_select ON public.client_debts_transactions;
CREATE POLICY debt_transactions_select ON public.client_debts_transactions
  FOR SELECT
  USING (
    client_id = auth.uid() OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- ============================================================================
-- PASO 12: GRANTS (Permisos de ejecución)
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.mark_order_not_delivered TO authenticated;
GRANT EXECUTE ON FUNCTION public.dispute_debt TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_dispute TO authenticated;
GRANT EXECUTE ON FUNCTION public.forgive_debt TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_client_suspension TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_client_debts TO authenticated;

-- ============================================================================
-- PASO 10: CONFIGURAR STORAGE RLS POLICIES PARA EVIDENCIAS
-- ============================================================================
-- Crear políticas para permitir subir y ver evidencias fotográficas

-- ⚠️ IMPORTANTE: Asegúrate de que el bucket "documents" existe antes de ejecutar estas políticas
-- Si no existe, créalo desde: Supabase Dashboard > Storage > Create bucket
-- Nombre: documents
-- Public: false
-- Allowed MIME types: image/jpeg, image/png, image/jpg, image/webp
-- File size limit: 5 MB

-- Política 1: Permitir a usuarios autenticados subir sus propias evidencias
DO $$
BEGIN
  -- Eliminar política existente si existe
  DELETE FROM storage.policies WHERE id = 'delivery-evidence-upload';
  
  -- Crear nueva política
  INSERT INTO storage.policies (id, bucket_id, name, definition, command)
  VALUES (
    'delivery-evidence-upload',
    'documents',
    'Delivery agents can upload evidence',
    '(bucket_id = ''documents''::text AND (storage.foldername(name))[1] = ''delivery-evidence''::text AND (auth.uid())::text = (storage.foldername(name))[2])',
    'INSERT'
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Error creating upload policy: %', SQLERRM;
END $$;

-- Política 2: Permitir a usuarios autenticados ver evidencias
DO $$
BEGIN
  DELETE FROM storage.policies WHERE id = 'delivery-evidence-select';
  
  INSERT INTO storage.policies (id, bucket_id, name, definition, command)
  VALUES (
    'delivery-evidence-select',
    'documents',
    'Users can view delivery evidence',
    '(bucket_id = ''documents''::text AND (storage.foldername(name))[1] = ''delivery-evidence''::text)',
    'SELECT'
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Error creating select policy: %', SQLERRM;
END $$;

-- Política 3: Permitir a admins ver todas las evidencias
DO $$
BEGIN
  DELETE FROM storage.policies WHERE id = 'delivery-evidence-admin-select';
  
  INSERT INTO storage.policies (id, bucket_id, name, definition, command)
  VALUES (
    'delivery-evidence-admin-select',
    'documents',
    'Admins can view all delivery evidence',
    '(bucket_id = ''documents''::text AND (storage.foldername(name))[1] = ''delivery-evidence''::text AND EXISTS (SELECT 1 FROM public.users WHERE users.id = auth.uid() AND users.role = ''admin''::text))',
    'SELECT'
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Error creating admin policy: %', SQLERRM;
END $$;

-- ============================================================================
-- FIN DEL SCRIPT
-- ============================================================================

-- Para verificar que todo se instaló correctamente:
SELECT 
  'Tables created' as check_type,
  COUNT(*) as count
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name IN ('client_debts', 'client_account_suspensions', 'client_debts_transactions')
UNION ALL
SELECT 
  'Functions created' as check_type,
  COUNT(*) as count
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN (
    'mark_order_not_delivered',
    'dispute_debt',
    'resolve_dispute',
    'forgive_debt',
    'check_client_suspension',
    'get_client_debts'
  );
