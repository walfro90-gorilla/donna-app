-- =============================================================================
-- BILLING DUAL MODEL - 05 CRON JOBS (pg_cron)
--
-- Dos jobs diarios:
--   1) fn_generate_subscription_invoices() — al acercarse el fin del periodo
--      genera la próxima invoice e avanza current_period_start/end.
--   2) fn_suspend_overdue_subscriptions() — pasa invoices vencidas + grace
--      a 'overdue' y suspende la suscripción.
--
-- Nota: pg_cron corre en UTC. Las horas elegidas (08:00/09:00 UTC = 02/03 MX
-- aprox según DST) son aceptables para procesos diarios sin SLA estricto.
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1) fn_generate_subscription_invoices
--    Por cada suscripción cuyo current_period_end ya pasó o vence en <= 24h:
--    genera la invoice del próximo periodo y avanza el periodo.
--    Idempotente por UNIQUE (subscription_id, period_start).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_generate_subscription_invoices()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec record;
  v_count integer := 0;
  v_new_period_start timestamptz;
  v_new_period_end   timestamptz;
BEGIN
  FOR rec IN
    SELECT s.id, s.account_id, s.monthly_fee, s.current_period_end
    FROM public.subscriptions s
    WHERE s.status <> 'cancelled'
      AND s.current_period_end <= now() + INTERVAL '1 day'
  LOOP
    v_new_period_start := rec.current_period_end;
    v_new_period_end   := v_new_period_start + INTERVAL '1 month';

    BEGIN
      INSERT INTO public.subscription_invoices (
        subscription_id, account_id, period_start, period_end, amount, status, due_date
      ) VALUES (
        rec.id, rec.account_id, v_new_period_start, v_new_period_end,
        rec.monthly_fee, 'pending', v_new_period_end
      );
      v_count := v_count + 1;

      -- Avanzar el periodo activo
      UPDATE public.subscriptions
      SET current_period_start = v_new_period_start,
          current_period_end   = v_new_period_end
      WHERE id = rec.id;

    EXCEPTION WHEN unique_violation THEN
      -- Ya existe la invoice de ese periodo: nada que hacer.
      NULL;
    END;
  END LOOP;

  RETURN jsonb_build_object('generated', v_count, 'ran_at', now());
END;
$$;

-- =============================================================================
-- 2) fn_suspend_overdue_subscriptions
--    Marca como 'overdue' las invoices con due_date + grace_days < now().
--    Suspende la suscripción correspondiente.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_suspend_overdue_subscriptions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_grace_days integer;
  v_suspended_count integer := 0;
  v_overdue_count integer := 0;
  rec record;
BEGIN
  SELECT COALESCE(value::integer, 7) INTO v_grace_days
  FROM public.platform_settings WHERE key = 'subscription_grace_days';
  v_grace_days := COALESCE(v_grace_days, 7);

  -- Marcar overdue
  WITH upd AS (
    UPDATE public.subscription_invoices
    SET status = 'overdue'
    WHERE status = 'pending'
      AND due_date + (v_grace_days || ' days')::interval < now()
    RETURNING id
  )
  SELECT COUNT(*) INTO v_overdue_count FROM upd;

  -- Suspender suscripciones que tengan al menos una invoice 'overdue'
  WITH upd AS (
    UPDATE public.subscriptions s
    SET status = 'suspended', suspended_at = now()
    WHERE s.status IN ('active', 'past_due')
      AND EXISTS (
        SELECT 1 FROM public.subscription_invoices i
        WHERE i.subscription_id = s.id AND i.status = 'overdue'
      )
    RETURNING id
  )
  SELECT COUNT(*) INTO v_suspended_count FROM upd;

  RETURN jsonb_build_object(
    'overdue_invoices', v_overdue_count,
    'suspended_subscriptions', v_suspended_count,
    'ran_at', now()
  );
END;
$$;

-- =============================================================================
-- 3) Programar jobs en pg_cron (idempotente: unschedule existente primero)
--    Generar invoices: diario a las 08:00 UTC.
--    Suspender vencidos: diario a las 09:00 UTC.
-- =============================================================================

DO $$
DECLARE
  v_job_id bigint;
BEGIN
  -- Job 1: generación de invoices
  SELECT jobid INTO v_job_id FROM cron.job WHERE jobname = 'billing_generate_invoices';
  IF v_job_id IS NOT NULL THEN PERFORM cron.unschedule(v_job_id); END IF;

  PERFORM cron.schedule(
    'billing_generate_invoices',
    '0 8 * * *',
    $cmd$SELECT public.fn_generate_subscription_invoices();$cmd$
  );

  -- Job 2: suspensión por vencimiento
  SELECT jobid INTO v_job_id FROM cron.job WHERE jobname = 'billing_suspend_overdue';
  IF v_job_id IS NOT NULL THEN PERFORM cron.unschedule(v_job_id); END IF;

  PERFORM cron.schedule(
    'billing_suspend_overdue',
    '0 9 * * *',
    $cmd$SELECT public.fn_suspend_overdue_subscriptions();$cmd$
  );
END;
$$;

COMMIT;

-- Verificación manual:
--   SELECT jobname, schedule, command FROM cron.job WHERE jobname LIKE 'billing_%';
--   SELECT public.fn_generate_subscription_invoices();
--   SELECT public.fn_suspend_overdue_subscriptions();
