-- ============================================================================
-- Purpose: Add 'not_delivered' status and client debt tracking system
-- Date: 2025-01-16
-- Description: Permite al repartidor marcar órdenes como no entregadas cuando
--              el cliente no está disponible o la dirección es falsa.
--              El cliente queda con adeudo y no puede ordenar hasta liquidar.
-- ============================================================================
--
-- FLUJO FINANCIERO:
-- 1. Cliente debe pagar la orden completa (subtotal + delivery_fee)
-- 2. Restaurant recibe su pago neto (subtotal - comisión)
-- 3. Repartidor recibe su pago de delivery (85% de delivery_fee)
-- 4. Plataforma absorbe el costo inicialmente
-- 5. Se crea adeudo del cliente hacia la plataforma
-- 6. Balance = 0 (todo cuadra)
-- 7. Cliente bloqueado hasta liquidar adeudo
--
-- INSPIRED BY: DoorDash, Uber Eats, Rappi (manejo de no-shows y entregas fallidas)
-- ============================================================================

BEGIN;

-- ============================================================================
-- STEP 1: Extend order status enum to include 'not_delivered'
-- ============================================================================

-- Check if status constraint exists and update it
DO $$
BEGIN
  -- Drop existing constraint if it exists
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'orders_status_check' 
    AND conrelid = 'public.orders'::regclass
  ) THEN
    ALTER TABLE public.orders DROP CONSTRAINT orders_status_check;
  END IF;

  -- Add new constraint with 'not_delivered' status
  ALTER TABLE public.orders ADD CONSTRAINT orders_status_check
    CHECK (status = ANY (ARRAY[
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
      'not_delivered'::text,  -- NEW STATUS
      'cancelled'::text,
      'canceled'::text
    ]));
    
  RAISE NOTICE '✅ Updated orders.status constraint to include not_delivered';
END $$;

-- ============================================================================
-- STEP 2: Create client_debts table to track unpaid orders
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.client_debts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_user_id uuid NOT NULL REFERENCES public.users(id),
  order_id uuid NOT NULL REFERENCES public.orders(id),
  amount numeric NOT NULL CHECK (amount > 0),
  reason text NOT NULL CHECK (reason IN ('not_delivered', 'client_no_show', 'fake_address', 'other')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'forgiven', 'disputed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz,
  payment_method text,
  notes text,
  metadata jsonb DEFAULT '{}'::jsonb,
  
  -- Audit fields
  marked_by_user_id uuid REFERENCES public.users(id),
  resolved_by_user_id uuid REFERENCES public.users(id),
  
  CONSTRAINT unique_debt_per_order UNIQUE (order_id)
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_client_debts_client ON public.client_debts(client_user_id);
CREATE INDEX IF NOT EXISTS idx_client_debts_status ON public.client_debts(status);
CREATE INDEX IF NOT EXISTS idx_client_debts_order ON public.client_debts(order_id);

COMMENT ON TABLE public.client_debts IS 'Tracks unpaid debts from clients due to failed deliveries';
COMMENT ON COLUMN public.client_debts.reason IS 'Reason for debt: not_delivered, client_no_show, fake_address, other';
COMMENT ON COLUMN public.client_debts.status IS 'Debt status: pending, paid, forgiven, disputed';

-- ============================================================================
-- STEP 3: Add debt tracking to client_profiles
-- ============================================================================

-- Add columns if they don't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'client_profiles' 
    AND column_name = 'has_pending_debt'
  ) THEN
    ALTER TABLE public.client_profiles 
    ADD COLUMN has_pending_debt boolean NOT NULL DEFAULT false;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'client_profiles' 
    AND column_name = 'total_debt_amount'
  ) THEN
    ALTER TABLE public.client_profiles 
    ADD COLUMN total_debt_amount numeric NOT NULL DEFAULT 0.00;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'client_profiles' 
    AND column_name = 'can_order'
  ) THEN
    ALTER TABLE public.client_profiles 
    ADD COLUMN can_order boolean NOT NULL DEFAULT true;
  END IF;
  
  RAISE NOTICE '✅ Added debt tracking columns to client_profiles';
END $$;

-- ============================================================================
-- STEP 4: Function to process 'not_delivered' orders
-- ============================================================================

CREATE OR REPLACE FUNCTION public.process_order_not_delivered()
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
  v_client_account_id uuid;

  v_payment_method text;
  v_restaurant_user_id uuid;
  v_short_order text;
  v_client_debt_amount numeric(10,2);
BEGIN
  -- Only process when order transitions to 'not_delivered'
  IF NEW.status = 'not_delivered' AND (OLD.status IS DISTINCT FROM 'not_delivered') THEN
    v_short_order := LEFT(NEW.id::text, 8);
    
    RAISE NOTICE '🚫 [not_delivered] Processing failed delivery for order %', v_short_order;

    -- Get restaurant configuration
    SELECT COALESCE(r.commission_bps, 1500), r.user_id
    INTO v_commission_bps, v_restaurant_user_id
    FROM public.restaurants r
    WHERE r.id = NEW.restaurant_id;

    IF v_restaurant_user_id IS NULL THEN
      RAISE WARNING '[not_delivered] Restaurant not found for order %', NEW.id;
      RETURN NEW;
    END IF;

    -- Calculate amounts (same as delivered)
    v_commission_bps := GREATEST(0, LEAST(3000, v_commission_bps));
    v_commission_rate := v_commission_bps / 10000.0;
    v_platform_commission := ROUND(COALESCE(NEW.subtotal, NEW.total_amount - COALESCE(NEW.delivery_fee, 0)) * v_commission_rate, 2);
    v_restaurant_net := ROUND(COALESCE(NEW.subtotal, NEW.total_amount - COALESCE(NEW.delivery_fee, 0)) - v_platform_commission, 2);
    v_delivery_earning := ROUND(COALESCE(NEW.delivery_fee, 0) * 0.85, 2);
    v_platform_delivery_margin := ROUND(COALESCE(NEW.delivery_fee, 0) - v_delivery_earning, 2);
    v_payment_method := COALESCE(NEW.payment_method, 'cash');
    
    -- Client owes the full order amount
    v_client_debt_amount := NEW.total_amount;

    -- Resolve accounts
    SELECT a.id INTO v_restaurant_account_id
    FROM public.accounts a
    WHERE a.user_id = v_restaurant_user_id AND a.account_type = 'restaurant'
    ORDER BY a.created_at DESC LIMIT 1;

    IF NEW.delivery_agent_id IS NOT NULL THEN
      SELECT a.id INTO v_delivery_account_id
      FROM public.accounts a
      WHERE a.user_id = NEW.delivery_agent_id AND a.account_type = 'delivery_agent'
      ORDER BY a.created_at DESC LIMIT 1;
    END IF;

    SELECT a.id INTO v_platform_revenue_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_revenue'
    ORDER BY a.created_at DESC LIMIT 1;

    SELECT a.id INTO v_platform_payables_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_payables'
    ORDER BY a.created_at DESC LIMIT 1;
    
    -- Get or create client account
    SELECT a.id INTO v_client_account_id
    FROM public.accounts a
    WHERE a.user_id = NEW.user_id AND a.account_type = 'client'
    ORDER BY a.created_at DESC LIMIT 1;
    
    IF v_client_account_id IS NULL THEN
      INSERT INTO public.accounts (user_id, account_type, balance)
      VALUES (NEW.user_id, 'client', 0)
      RETURNING id INTO v_client_account_id;
    END IF;

    IF v_restaurant_account_id IS NULL OR v_platform_revenue_account_id IS NULL 
       OR v_platform_payables_account_id IS NULL OR v_client_account_id IS NULL THEN
      RAISE WARNING '[not_delivered] Missing core accounts for order %', NEW.id;
      RETURN NEW;
    END IF;

    -- ========================================================================
    -- FINANCIAL TRANSACTIONS (Zero-sum accounting)
    -- ========================================================================
    
    -- 1. Platform commission (credit)
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
    VALUES (
      v_platform_revenue_account_id,
      'PLATFORM_COMMISSION',
      v_platform_commission,
      NEW.id,
      'Comisión plataforma (no entregada) orden #' || v_short_order,
      jsonb_build_object(
        'commission_bps', v_commission_bps, 
        'rate', v_commission_rate, 
        'payment_method', v_payment_method,
        'order_status', 'not_delivered'
      )
    )
    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

    -- 2. Restaurant net payment (credit) - Restaurant still gets paid
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
    VALUES (
      v_restaurant_account_id,
      'RESTAURANT_PAYABLE',
      v_restaurant_net,
      NEW.id,
      'Pago neto restaurante (no entregada) orden #' || v_short_order,
      jsonb_build_object(
        'commission_bps', v_commission_bps, 
        'rate', v_commission_rate, 
        'payment_method', v_payment_method,
        'order_status', 'not_delivered'
      )
    )
    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

    -- 3. Delivery earning (credit) - Delivery agent still gets paid for the attempt
    IF v_delivery_account_id IS NOT NULL AND COALESCE(NEW.delivery_fee, 0) > 0 THEN
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_delivery_account_id,
        'DELIVERY_EARNING',
        v_delivery_earning,
        NEW.id,
        'Ganancia delivery (intento fallido) orden #' || v_short_order,
        jsonb_build_object(
          'delivery_fee', COALESCE(NEW.delivery_fee, 0), 
          'pct', 0.85, 
          'payment_method', v_payment_method,
          'order_status', 'not_delivered'
        )
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_DELIVERY_MARGIN',
        v_platform_delivery_margin,
        NEW.id,
        'Margen plataforma delivery (no entregada) orden #' || v_short_order,
        jsonb_build_object(
          'delivery_fee', COALESCE(NEW.delivery_fee, 0), 
          'pct', 0.15, 
          'payment_method', v_payment_method,
          'order_status', 'not_delivered'
        )
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
    END IF;

    -- 4. Platform absorbs the cost initially (debit from platform_payables)
    -- This balances the equation to zero
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
    VALUES (
      v_platform_payables_account_id,
      'CASH_COLLECTED',
      -NEW.total_amount,
      NEW.id,
      'Plataforma absorbe costo (no entregada) orden #' || v_short_order,
      jsonb_build_object(
        'total', NEW.total_amount, 
        'payment_method', v_payment_method,
        'order_status', 'not_delivered',
        'platform_absorbs', true
      )
    )
    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

    -- ========================================================================
    -- CREATE CLIENT DEBT RECORD
    -- ========================================================================
    
    INSERT INTO public.client_debts (
      client_user_id,
      order_id,
      amount,
      reason,
      status,
      marked_by_user_id,
      notes,
      metadata
    )
    VALUES (
      NEW.user_id,
      NEW.id,
      v_client_debt_amount,
      'not_delivered',
      'pending',
      NEW.delivery_agent_id,
      'Cliente no disponible o dirección incorrecta. Orden marcada como no entregada.',
      jsonb_build_object(
        'order_id', NEW.id,
        'delivery_agent_id', NEW.delivery_agent_id,
        'restaurant_id', NEW.restaurant_id,
        'subtotal', COALESCE(NEW.subtotal, 0),
        'delivery_fee', COALESCE(NEW.delivery_fee, 0),
        'total_amount', NEW.total_amount,
        'payment_method', v_payment_method,
        'delivery_address', NEW.delivery_address,
        'marked_at', now()
      )
    )
    ON CONFLICT ON CONSTRAINT unique_debt_per_order DO NOTHING;

    -- ========================================================================
    -- UPDATE CLIENT PROFILE - BLOCK FROM ORDERING
    -- ========================================================================
    
    UPDATE public.client_profiles
    SET 
      has_pending_debt = true,
      total_debt_amount = total_debt_amount + v_client_debt_amount,
      can_order = false,
      updated_at = now()
    WHERE user_id = NEW.user_id;
    
    -- If client profile doesn't exist, create it
    IF NOT FOUND THEN
      INSERT INTO public.client_profiles (
        user_id,
        has_pending_debt,
        total_debt_amount,
        can_order,
        status
      )
      VALUES (
        NEW.user_id,
        true,
        v_client_debt_amount,
        false,
        'suspended'
      )
      ON CONFLICT (user_id) DO UPDATE SET
        has_pending_debt = true,
        total_debt_amount = EXCLUDED.total_debt_amount,
        can_order = false,
        status = 'suspended';
    END IF;

    -- ========================================================================
    -- CREATE SETTLEMENTS (Same as normal delivery)
    -- ========================================================================
    
    -- Platform pays restaurant (since platform absorbed the cost)
    INSERT INTO public.settlements (
      payer_account_id, 
      receiver_account_id, 
      amount, 
      status, 
      confirmation_code, 
      initiated_at, 
      notes
    )
    VALUES (
      v_platform_payables_account_id, 
      v_restaurant_account_id, 
      v_restaurant_net, 
      'pending', 
      LPAD(FLOOR(RANDOM()*10000)::text, 4, '0'), 
      now(), 
      'Orden #' || v_short_order || ' (no entregada → restaurant)'
    );

    -- Platform pays delivery agent (since platform absorbed the cost)
    IF v_delivery_account_id IS NOT NULL AND v_delivery_earning > 0 THEN
      INSERT INTO public.settlements (
        payer_account_id, 
        receiver_account_id, 
        amount, 
        status, 
        confirmation_code, 
        initiated_at, 
        notes
      )
      VALUES (
        v_platform_payables_account_id, 
        v_delivery_account_id, 
        v_delivery_earning, 
        'pending', 
        LPAD(FLOOR(RANDOM()*10000)::text, 4, '0'), 
        now(), 
        'Orden #' || v_short_order || ' (no entregada → delivery)'
      );
    END IF;

    RAISE NOTICE '✅ [not_delivered] Order % processed. Client debt: %. Client blocked from ordering.', 
      v_short_order, v_client_debt_amount;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 5: Create trigger for not_delivered status
-- ============================================================================

DROP TRIGGER IF EXISTS trg_on_order_not_delivered ON public.orders;
CREATE TRIGGER trg_on_order_not_delivered
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'not_delivered')
EXECUTE FUNCTION public.process_order_not_delivered();

-- ============================================================================
-- STEP 6: Function to check if client can order
-- ============================================================================

CREATE OR REPLACE FUNCTION public.can_client_place_order(p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_can_order boolean;
  v_has_debt boolean;
BEGIN
  SELECT 
    COALESCE(cp.can_order, true),
    COALESCE(cp.has_pending_debt, false)
  INTO v_can_order, v_has_debt
  FROM public.client_profiles cp
  WHERE cp.user_id = p_user_id;
  
  -- If no profile exists, client can order
  IF NOT FOUND THEN
    RETURN true;
  END IF;
  
  -- Client cannot order if they have pending debt
  IF v_has_debt THEN
    RETURN false;
  END IF;
  
  RETURN v_can_order;
END;
$$;

-- ============================================================================
-- STEP 7: Function to resolve client debt (when client pays)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.resolve_client_debt(
  p_debt_id uuid,
  p_payment_method text DEFAULT 'card',
  p_resolved_by_user_id uuid DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_client_user_id uuid;
  v_debt_amount numeric;
  v_client_remaining_debt numeric;
BEGIN
  -- Get debt details
  SELECT client_user_id, amount
  INTO v_client_user_id, v_debt_amount
  FROM public.client_debts
  WHERE id = p_debt_id AND status = 'pending';
  
  IF NOT FOUND THEN
    RAISE WARNING 'Debt % not found or already resolved', p_debt_id;
    RETURN false;
  END IF;
  
  -- Mark debt as paid
  UPDATE public.client_debts
  SET 
    status = 'paid',
    paid_at = now(),
    payment_method = p_payment_method,
    resolved_by_user_id = p_resolved_by_user_id,
    notes = COALESCE(p_notes, notes)
  WHERE id = p_debt_id;
  
  -- Update client profile
  UPDATE public.client_profiles
  SET 
    total_debt_amount = GREATEST(0, total_debt_amount - v_debt_amount),
    updated_at = now()
  WHERE user_id = v_client_user_id
  RETURNING total_debt_amount INTO v_client_remaining_debt;
  
  -- If no remaining debt, unblock client
  IF v_client_remaining_debt = 0 THEN
    UPDATE public.client_profiles
    SET 
      has_pending_debt = false,
      can_order = true,
      status = 'active',
      updated_at = now()
    WHERE user_id = v_client_user_id;
    
    RAISE NOTICE '✅ Client % debt cleared. Account unblocked.', v_client_user_id;
  END IF;
  
  RETURN true;
END;
$$;

-- ============================================================================
-- STEP 8: View to see client debts summary
-- ============================================================================

CREATE OR REPLACE VIEW public.v_client_debts_summary AS
SELECT 
  cd.id AS debt_id,
  cd.client_user_id,
  u.name AS client_name,
  u.email AS client_email,
  u.phone AS client_phone,
  cd.order_id,
  o.created_at AS order_date,
  cd.amount AS debt_amount,
  cd.reason,
  cd.status AS debt_status,
  cd.created_at AS debt_created_at,
  cd.paid_at,
  cd.notes,
  r.name AS restaurant_name,
  da.name AS delivery_agent_name,
  cp.total_debt_amount AS client_total_debt,
  cp.can_order
FROM public.client_debts cd
JOIN public.users u ON cd.client_user_id = u.id
JOIN public.orders o ON cd.order_id = o.id
LEFT JOIN public.restaurants r ON o.restaurant_id = r.id
LEFT JOIN public.users da ON cd.marked_by_user_id = da.id
LEFT JOIN public.client_profiles cp ON cd.client_user_id = cp.user_id
ORDER BY cd.created_at DESC;

-- ============================================================================
-- STEP 9: Enable RLS policies for client_debts
-- ============================================================================

ALTER TABLE public.client_debts ENABLE ROW LEVEL SECURITY;

-- Admins can see all debts
CREATE POLICY "Admins can view all client debts"
  ON public.client_debts
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Clients can see their own debts
CREATE POLICY "Clients can view their own debts"
  ON public.client_debts
  FOR SELECT
  TO authenticated
  USING (client_user_id = auth.uid());

-- Delivery agents can create debts for orders they deliver
CREATE POLICY "Delivery agents can create debts"
  ON public.client_debts
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'delivery_agent'
    )
    AND marked_by_user_id = auth.uid()
  );

-- Admins can update debts
CREATE POLICY "Admins can update client debts"
  ON public.client_debts
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- ============================================================================
-- STEP 10: Add helpful comments
-- ============================================================================

COMMENT ON FUNCTION public.process_order_not_delivered() IS 
'Processes orders marked as not_delivered. Creates debt record, blocks client from ordering, and ensures zero-sum accounting where platform absorbs cost initially.';

COMMENT ON FUNCTION public.can_client_place_order(uuid) IS 
'Checks if a client can place new orders. Returns false if client has pending debts.';

COMMENT ON FUNCTION public.resolve_client_debt(uuid, text, uuid, text) IS 
'Marks a client debt as paid and unblocks client if no remaining debts exist.';

COMMENT ON VIEW public.v_client_debts_summary IS 
'Comprehensive view of all client debts with order and user details.';

-- ============================================================================
-- SUCCESS MESSAGE
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '
  ============================================================================
  ✅ NOT_DELIVERED STATUS AND CLIENT DEBT SYSTEM INSTALLED SUCCESSFULLY
  ============================================================================
  
  NEW FEATURES:
  ✓ Orders can now be marked as "not_delivered"
  ✓ Client debt tracking system created
  ✓ Clients with pending debts cannot place new orders
  ✓ Zero-sum accounting maintained (platform absorbs cost initially)
  ✓ Restaurant and delivery agent still get paid
  ✓ Admin panel can view and resolve client debts
  
  TABLES CREATED:
  • client_debts - Tracks all client debts
  
  COLUMNS ADDED TO client_profiles:
  • has_pending_debt (boolean)
  • total_debt_amount (numeric)
  • can_order (boolean)
  
  FUNCTIONS CREATED:
  • process_order_not_delivered() - Handles not_delivered orders
  • can_client_place_order() - Checks if client can order
  • resolve_client_debt() - Resolves paid debts
  
  VIEWS CREATED:
  • v_client_debts_summary - Admin view of all debts
  
  NEXT STEPS FOR FLUTTER:
  1. Update OrderStatus enum to include "not_delivered"
  2. Add button in delivery screen to mark as not_delivered
  3. Show confirmation modal before marking (reason, notes, etc)
  4. Block checkout for clients with pending debts
  5. Create admin screen to manage client debts
  6. Add payment screen for clients to clear debts
  
  ============================================================================
  ';
END $$;

COMMIT;
