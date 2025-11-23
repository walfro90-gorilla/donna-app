-- =====================================================================
-- CLIENT DEFAULT (Falla de Cliente) - Asientos de doble entrada Balance 0
-- Crea una RPC atómica que:
--  1) Paga al restaurante su neto (ORDER_REVENUE +restaurant_net)
--  2) Paga al repartidor su ganancia (DELIVERY_EARNING +delivery_earning)
--  3) Registra la deuda completa al cliente (CLIENT_DEBT -total_amount)
--  4) Registra comisión plataforma (PLATFORM_COMMISSION +commission)
--  5) Registra margen delivery plataforma (PLATFORM_DELIVERY_MARGIN +platform_delivery_margin)
-- Mantiene Balance Cero. Idempotente por orden.
-- =====================================================================

DO $$
DECLARE
  v_conname text;
  v_condef  text;
BEGIN
  -- Asegurar que el tipo de transacción permite los nuevos valores.
  -- Si no existe constraint sobre type: lo creamos.
  -- Si existe y no contiene ambos valores nuevos: lo reemplazamos.
  SELECT c.conname, pg_get_constraintdef(c.oid)
    INTO v_conname, v_condef
  FROM pg_constraint c
  JOIN pg_class t ON c.conrelid = t.oid
  JOIN pg_namespace n ON t.relnamespace = n.oid
  WHERE n.nspname = 'public'
    AND t.relname = 'account_transactions'
    AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) ILIKE '%type%'
  LIMIT 1;

  IF v_conname IS NULL THEN
    -- No hay constraint todavía: crearlo
    EXECUTE 'ALTER TABLE public.account_transactions
      ADD CONSTRAINT account_transactions_type_check
      CHECK (type IN (
        ''ORDER_REVENUE'',''PLATFORM_COMMISSION'',''DELIVERY_EARNING'',''CASH_COLLECTED'',
        ''SETTLEMENT_PAYMENT'',''SETTLEMENT_RECEPTION'',''CLIENT_DEBT'',''PLATFORM_DELIVERY_MARGIN''
      ))';
  ELSE
    -- Hay constraint existente: validar si ya incluye los nuevos valores
    IF (v_condef NOT ILIKE '%CLIENT_DEBT%') OR (v_condef NOT ILIKE '%PLATFORM_DELIVERY_MARGIN%') THEN
      EXECUTE format('ALTER TABLE public.account_transactions DROP CONSTRAINT %I', v_conname);
      EXECUTE 'ALTER TABLE public.account_transactions
        ADD CONSTRAINT account_transactions_type_check
        CHECK (type IN (
          ''ORDER_REVENUE'',''PLATFORM_COMMISSION'',''DELIVERY_EARNING'',''CASH_COLLECTED'',
          ''SETTLEMENT_PAYMENT'',''SETTLEMENT_RECEPTION'',''CLIENT_DEBT'',''PLATFORM_DELIVERY_MARGIN''
        ))';
    END IF;
  END IF;
END $$;

-- =====================================================================
-- RPC principal: marca orden como falla de cliente y genera asientos
-- =====================================================================
CREATE OR REPLACE FUNCTION public.rpc_post_client_default(
  p_order_id uuid,
  p_reason text DEFAULT 'Falla de Cliente'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_restaurant_account uuid;
  v_delivery_account uuid;
  v_client_account uuid;
  v_platform_revenue uuid;
  v_subtotal numeric;
  v_commission numeric;
  v_restaurant_net numeric;
  v_delivery_earning numeric;
  v_platform_delivery_margin numeric;
  v_now timestamptz := now();
  v_actor uuid := auth.uid();
  v_status_changed boolean := false;
BEGIN
  -- Leer orden
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Orden % no existe', p_order_id;
  END IF;

  -- Idempotencia: si ya existen transacciones de esta orden con metadata.reason = 'client_default', abortar
  IF EXISTS (
    SELECT 1 FROM public.account_transactions 
    WHERE order_id = p_order_id 
      AND (metadata ->> 'reason') = 'client_default'
  ) THEN
    RETURN jsonb_build_object('success', true, 'skipped', true, 'message', 'Asientos ya creados previamente');
  END IF;

  -- Resolver cuentas
  -- Restaurante (por restaurant_id -> restaurants.user_id -> accounts)
  SELECT a.id INTO v_restaurant_account
  FROM public.accounts a
  JOIN public.restaurants r ON r.user_id = a.user_id
  WHERE r.id = v_order.restaurant_id
  ORDER BY (a.account_type ILIKE 'restaur%') DESC, a.created_at ASC
  LIMIT 1;

  -- Repartidor (por delivery_agent_id)
  SELECT a.id INTO v_delivery_account
  FROM public.accounts a
  WHERE a.user_id = v_order.delivery_agent_id
  ORDER BY (a.account_type IN ('delivery_agent','repartidor')) DESC, a.created_at ASC
  LIMIT 1;

  -- Cliente: asegurar perfil/cuenta y resolver account_id
  PERFORM public.ensure_client_profile_and_account(v_order.user_id);
  SELECT id INTO v_client_account FROM public.accounts
  WHERE user_id = v_order.user_id AND account_type = 'client'
  LIMIT 1;

  -- Plataforma (ingresos)
  SELECT id INTO v_platform_revenue
  FROM public.accounts
  WHERE account_type = 'platform_revenue'
  LIMIT 1;
  IF v_platform_revenue IS NULL THEN
    SELECT id INTO v_platform_revenue FROM public.accounts
    WHERE user_id = '00000000-0000-0000-0000-000000000001'::uuid
    LIMIT 1;
  END IF;

  IF v_restaurant_account IS NULL OR v_delivery_account IS NULL OR v_client_account IS NULL OR v_platform_revenue IS NULL THEN
    RAISE EXCEPTION 'No se pudieron resolver cuentas necesarias (restaurante/repartidor/cliente/plataforma)';
  END IF;

  -- Cálculos según esquema actual (20% comisión sobre subtotal, 85% para repartidor)
  v_subtotal := COALESCE(v_order.total_amount, 0) - COALESCE(v_order.delivery_fee, 0);
  v_commission := ROUND(v_subtotal * 0.20, 2);
  v_restaurant_net := v_subtotal - v_commission;
  v_delivery_earning := ROUND(COALESCE(v_order.delivery_fee, 0) * 0.85, 2);
  v_platform_delivery_margin := COALESCE(v_order.delivery_fee, 0) - v_delivery_earning;

  -- Validaciones mínimas
  IF COALESCE(v_order.total_amount, 0) <= 0 THEN
    RAISE EXCEPTION 'La orden % no tiene total_amount válido', p_order_id;
  END IF;

  -- ===================================================================
  -- Asientos (5) - con metadata reason = client_default
  -- ===================================================================

  -- 1) Restaurante: ingreso neto
  INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)
  VALUES (
    v_restaurant_account,
    'ORDER_REVENUE',
    v_restaurant_net,
    p_order_id,
    format('Ingreso neto por falla de cliente - Orden #%s', LEFT(p_order_id::text, 8)),
    jsonb_build_object('reason','client_default','subtotal', v_subtotal, 'commission', v_commission),
    v_now
  );

  -- 2) Repartidor: ganancia de envío
  IF v_delivery_earning > 0 THEN
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)
    VALUES (
      v_delivery_account,
      'DELIVERY_EARNING',
      v_delivery_earning,
      p_order_id,
      format('Ganancia delivery por falla de cliente - Orden #%s', LEFT(p_order_id::text, 8)),
      jsonb_build_object('reason','client_default','delivery_fee', v_order.delivery_fee),
      v_now
    );
  END IF;

  -- 3) Cliente: deuda por el total de la orden
  INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)
  VALUES (
    v_client_account,
    'CLIENT_DEBT',
    -COALESCE(v_order.total_amount, 0),
    p_order_id,
    format('Deuda por falla de cliente - Orden #%s', LEFT(p_order_id::text, 8)),
    jsonb_build_object('reason','client_default'),
    v_now
  );

  -- 4) Plataforma: comisión sobre la comida
  IF v_commission > 0 THEN
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)
    VALUES (
      v_platform_revenue,
      'PLATFORM_COMMISSION',
      v_commission,
      p_order_id,
      format('Comisión plataforma 20%% - Orden #%s', LEFT(p_order_id::text, 8)),
      jsonb_build_object('reason','client_default','subtotal', v_subtotal),
      v_now
    );
  END IF;

  -- 5) Plataforma: margen delivery (fee - pago a repartidor)
  IF v_platform_delivery_margin > 0 THEN
    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)
    VALUES (
      v_platform_revenue,
      'PLATFORM_DELIVERY_MARGIN',
      v_platform_delivery_margin,
      p_order_id,
      format('Margen delivery - Orden #%s', LEFT(p_order_id::text, 8)),
      jsonb_build_object('reason','client_default','delivery_fee', v_order.delivery_fee),
      v_now
    );
  END IF;

  -- Recalcular balances de las cuatro cuentas implicadas
  PERFORM public.rpc_recompute_account_balance(v_restaurant_account);
  PERFORM public.rpc_recompute_account_balance(v_delivery_account);
  PERFORM public.rpc_recompute_account_balance(v_client_account);
  PERFORM public.rpc_recompute_account_balance(v_platform_revenue);

  -- Opcional: Marcar la orden como cancelada si aún no lo está y registrar el evento
  IF v_order.status <> 'canceled' THEN
    UPDATE public.orders
    SET status = 'canceled', updated_at = v_now
    WHERE id = p_order_id;
    v_status_changed := true;
  END IF;

  -- Registrar en order_status_updates (no hace fallar si la tabla/campos difieren)
  BEGIN
    INSERT INTO public.order_status_updates (
      order_id,
      status,
      actor_role,
      actor_id,
      updated_by_user_id,
      metadata,
      created_at
    ) VALUES (
      p_order_id,
      'canceled',
      'admin',
      v_actor,
      v_actor,
      jsonb_build_object('reason','client_default','note', p_reason),
      v_now
    );
  EXCEPTION WHEN others THEN
    -- No romper la operación por problemas de tracking
    NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'posted', 5,
    'order_status_marked_canceled', v_status_changed,
    'amounts', jsonb_build_object(
      'subtotal', v_subtotal,
      'commission', v_commission,
      'restaurant_net', v_restaurant_net,
      'delivery_earning', v_delivery_earning,
      'platform_delivery_margin', v_platform_delivery_margin,
      'client_debt', COALESCE(v_order.total_amount,0)
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_post_client_default(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.rpc_post_client_default(uuid, text) TO authenticated, service_role;

-- Nota: Si UI/Frontend usa enum de transacciones, agregar valores CLIENT_DEBT y PLATFORM_DELIVERY_MARGIN.
-- =====================================================================
-- USO Y VERIFICACIÓN (Instrucciones)
-- =====================================================================
-- 1) Pre-requisitos recomendados:
--    - Ejecutar 93_client_profiles_and_accounts_autocreate.sql para habilitar client_profiles y cuentas 'client'.
--    - Ejecutar 50_fix_balance_zero_system.sql (o equivalente) para crear cuentas de plataforma
--      ('platform_revenue' y/o el usuario fijo 00000000-0000-0000-0000-000000000001).
--    - Asegurarse de tener la RPC public.rpc_recompute_account_balance disponible.
--
-- 2) Marcar una orden como "Falla de Cliente" y generar los asientos (5):
--    SELECT public.rpc_post_client_default(
--      p_order_id => '00000000-0000-0000-0000-0000000000AA'::uuid,
--      p_reason   => 'Cliente no pagó/No show'
--    );
--
-- 3) Qué se registra:
--    - Restaurante: ORDER_REVENUE +neto comida (subtotal - 20% comisión)
--    - Repartidor: DELIVERY_EARNING +85% delivery_fee (si fee > 0)
--    - Cliente: CLIENT_DEBT -total_amount (deuda completa)
--    - Plataforma: PLATFORM_COMMISSION +20% del subtotal comida
--    - Plataforma: PLATFORM_DELIVERY_MARGIN +(delivery_fee - 85%)
--    Además: la orden se marca 'canceled' (si no lo estaba) y se escribe order_status_updates con reason=client_default.
--
-- 4) Verificaciones útiles:
--    -- a) Balance cero por orden
--    SELECT ROUND(COALESCE(SUM(amount),0), 2) as net
--    FROM public.account_transactions
--    WHERE order_id = '00000000-0000-0000-0000-0000000000AA'::uuid;
--    -- Debe devolver 0.00.
--
--    -- b) Suma por tipo de asiento para inspección
--    SELECT type, SUM(amount) FROM public.account_transactions
--    WHERE order_id = '00000000-0000-0000-0000-0000000000AA'::uuid
--    GROUP BY type
--    ORDER BY type;
--
--    -- c) Balances de cuentas afectadas (recomputados por RPC)
--    --    Use los account_id retornados por la RPC si se expone en UI/Logs.
