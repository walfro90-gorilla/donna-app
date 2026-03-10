-- =============================================================================
-- FIX: Eliminar auto-creación de liquidaciones en todos los triggers de entrega
-- =============================================================================
-- Problema: process_order_delivery_v4() y process_order_delivery_v3() crean
--           automáticamente rows en public.settlements al entregar una orden.
--           Las liquidaciones DEBEN crearse manualmente por el repartidor.
--
-- Solución: Reemplazar v4 (trigger activo) sin los INSERT INTO settlements.
--           Desactivar v3 por si acaso. Contabilidad zero-sum intacta.
--
-- Idempotente: CREATE OR REPLACE + DROP TRIGGER IF EXISTS
-- =============================================================================

BEGIN;

-- Desactivar todos los triggers de entrega anteriores por seguridad
DROP TRIGGER IF EXISTS trg_on_order_delivered_process_v3 ON public.orders;
DROP TRIGGER IF EXISTS trg_on_order_delivered_process_v4 ON public.orders;

-- =============================================================================
-- Reemplazar v4 SIN creación de settlements
-- (Mantiene toda la contabilidad zero-sum de account_transactions)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.process_order_delivery_v4()
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

  v_payment_method text;
  v_restaurant_user_id uuid;
  v_short_order text := '';
BEGIN
  IF NEW.status = 'delivered' AND (OLD.status IS DISTINCT FROM 'delivered') THEN
    v_short_order := LEFT(NEW.id::text, 8);

    -- Restaurant config
    SELECT COALESCE(r.commission_bps, 1500), r.user_id
    INTO v_commission_bps, v_restaurant_user_id
    FROM public.restaurants r
    WHERE r.id = NEW.restaurant_id;

    IF v_restaurant_user_id IS NULL THEN
      RAISE WARNING '[delivery_v4] Restaurant not found for order %', NEW.id;
      RETURN NEW;
    END IF;

    -- Clamp and compute amounts
    v_commission_bps := GREATEST(0, LEAST(3000, v_commission_bps));
    v_commission_rate := v_commission_bps / 10000.0;
    v_platform_commission := ROUND(COALESCE(NEW.subtotal, NEW.total_amount - COALESCE(NEW.delivery_fee, 0)) * v_commission_rate, 2);
    v_restaurant_net := ROUND(COALESCE(NEW.subtotal, NEW.total_amount - COALESCE(NEW.delivery_fee, 0)) - v_platform_commission, 2);
    v_delivery_earning := ROUND(COALESCE(NEW.delivery_fee, 0) * 0.85, 2);
    v_platform_delivery_margin := ROUND(COALESCE(NEW.delivery_fee, 0) - v_delivery_earning, 2);

    v_payment_method := COALESCE(NEW.payment_method, 'cash');

    -- Resolve accounts
    SELECT a.id INTO v_restaurant_account_id
    FROM public.accounts a
    WHERE a.user_id = v_restaurant_user_id AND a.account_type = 'restaurant'
    ORDER BY a.created_at DESC
    LIMIT 1;

    IF NEW.delivery_agent_id IS NOT NULL THEN
      SELECT a.id INTO v_delivery_account_id
      FROM public.accounts a
      WHERE a.user_id = NEW.delivery_agent_id AND a.account_type = 'delivery_agent'
      ORDER BY a.created_at DESC
      LIMIT 1;
    END IF;

    SELECT a.id INTO v_platform_revenue_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_revenue'
    ORDER BY a.created_at DESC
    LIMIT 1;

    SELECT a.id INTO v_platform_payables_account_id
    FROM public.accounts a
    WHERE a.account_type = 'platform_payables'
    ORDER BY a.created_at DESC
    LIMIT 1;

    IF v_restaurant_account_id IS NULL OR v_platform_revenue_account_id IS NULL OR v_platform_payables_account_id IS NULL THEN
      RAISE WARNING '[delivery_v4] Missing core accounts for order %', NEW.id;
      RETURN NEW;
    END IF;

    IF v_payment_method = 'card' THEN
      -- =====================================================================
      -- PAGO CON TARJETA: MercadoPago ya depositó en la plataforma
      -- =====================================================================

      -- Ingreso de la plataforma (comisión)
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_COMMISSION',
        v_platform_commission,
        NEW.id,
        'Comisión plataforma ' || v_commission_bps || 'bps orden #' || v_short_order,
        jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'card')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_DELIVERY_MARGIN',
        v_platform_delivery_margin,
        NEW.id,
        'Margen plataforma delivery 15% orden #' || v_short_order,
        jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.15, 'payment_method', 'card')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      -- Deuda de la plataforma hacia el restaurante (negativo en platform_payables)
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_payables_account_id,
        'RESTAURANT_PAYABLE',
        -v_restaurant_net,
        NEW.id,
        'Deuda con restaurante orden #' || v_short_order,
        jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'card')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      -- Crédito al restaurante
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_restaurant_account_id,
        'RESTAURANT_PAYABLE',
        v_restaurant_net,
        NEW.id,
        'Pago neto restaurante orden #' || v_short_order,
        jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'card')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      IF v_delivery_account_id IS NOT NULL AND COALESCE(NEW.delivery_fee, 0) > 0 THEN
        -- Deuda de la plataforma hacia el repartidor (negativo en platform_payables)
        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_platform_payables_account_id,
          'DELIVERY_EARNING',
          -v_delivery_earning,
          NEW.id,
          'Deuda con repartidor orden #' || v_short_order,
          jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.85, 'payment_method', 'card')
        )
        ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

        -- Crédito al repartidor
        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_delivery_account_id,
          'DELIVERY_EARNING',
          v_delivery_earning,
          NEW.id,
          'Ganancia delivery 85% orden #' || v_short_order,
          jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.85, 'payment_method', 'card')
        )
        ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
      END IF;

      -- NOTE: No auto-settlement. Settlements se crean manualmente via rpc_create_settlement.

    ELSE
      -- =====================================================================
      -- PAGO EN EFECTIVO: El repartidor cobra y debe entregar parte
      -- =====================================================================

      -- Ingreso de la plataforma (comisión)
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_COMMISSION',
        v_platform_commission,
        NEW.id,
        'Comisión plataforma ' || v_commission_bps || 'bps orden #' || v_short_order,
        jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'cash')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_platform_revenue_account_id,
        'PLATFORM_DELIVERY_MARGIN',
        v_platform_delivery_margin,
        NEW.id,
        'Margen plataforma delivery 15% orden #' || v_short_order,
        jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.15, 'payment_method', 'cash')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      -- Crédito al restaurante
      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
      VALUES (
        v_restaurant_account_id,
        'RESTAURANT_PAYABLE',
        v_restaurant_net,
        NEW.id,
        'Pago neto restaurante orden #' || v_short_order,
        jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', 'cash')
      )
      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

      IF v_delivery_account_id IS NOT NULL AND COALESCE(NEW.delivery_fee, 0) > 0 THEN
        -- Crédito al repartidor
        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_delivery_account_id,
          'DELIVERY_EARNING',
          v_delivery_earning,
          NEW.id,
          'Ganancia delivery 85% orden #' || v_short_order,
          jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.85, 'payment_method', 'cash')
        )
        ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;

        -- Efectivo recolectado (negativo — el repartidor tiene deuda con la plataforma)
        INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)
        VALUES (
          v_delivery_account_id,
          'CASH_COLLECTED',
          -NEW.total_amount,
          NEW.id,
          'Efectivo recolectado orden #' || v_short_order,
          jsonb_build_object('total', NEW.total_amount, 'payment_method', 'cash', 'collected_by_delivery', true)
        )
        ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;
      END IF;

      -- NOTE: No auto-settlement. Settlements se crean manualmente via rpc_create_settlement.

    END IF;

    RAISE NOTICE '✅ [delivery_v4] order % processed (method %, net_rest %, deliv %) [no auto-settlement]',
      NEW.id, v_payment_method, v_restaurant_net, v_delivery_earning;
  END IF;

  RETURN NEW;
END;
$$;

-- Rebind trigger
CREATE TRIGGER trg_on_order_delivered_process_v4
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'delivered')
EXECUTE FUNCTION public.process_order_delivery_v4();

COMMIT;
