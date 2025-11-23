-- =====================================================
-- FIX: Eliminar trigger roto que actualiza users.total_reviews
-- =====================================================
--
-- PROBLEMA:
--   El trigger update_average_ratings() intenta actualizar users.total_reviews
--   que ya NO EXISTE después del refactor 2025.
--
-- SOLUCIÓN:
--   Eliminar el trigger y la función, dejando que total_reviews y average_rating
--   se calculen dinámicamente desde la tabla reviews.
--
-- ESTRATEGIA:
--   - DROP todos los triggers relacionados
--   - DROP la función update_average_ratings()
--   - Mantener las columnas total_reviews y average_rating en profiles
--     (pueden usarse para caché manual o cron jobs futuros)
--
-- IDEMPOTENTE: Seguro correr múltiples veces
-- =====================================================

-- ====================================
-- PASO 1: Eliminar triggers existentes
-- ====================================

DO $$
BEGIN
  -- Trigger en INSERT
  IF EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'reviews'
      AND t.tgname = 'update_reviews_on_insert'
  ) THEN
    DROP TRIGGER update_reviews_on_insert ON public.reviews;
    RAISE NOTICE '✅ Trigger "update_reviews_on_insert" eliminado';
  ELSE
    RAISE NOTICE '⚠️  Trigger "update_reviews_on_insert" no existe (ya eliminado)';
  END IF;

  -- Trigger en UPDATE (por si acaso existe)
  IF EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'reviews'
      AND t.tgname = 'update_reviews_on_update'
  ) THEN
    DROP TRIGGER update_reviews_on_update ON public.reviews;
    RAISE NOTICE '✅ Trigger "update_reviews_on_update" eliminado';
  ELSE
    RAISE NOTICE '⚠️  Trigger "update_reviews_on_update" no existe (ya eliminado)';
  END IF;

  -- Trigger alternativo (por si tiene otro nombre)
  IF EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'reviews'
      AND t.tgname = 'trigger_update_average_ratings'
  ) THEN
    DROP TRIGGER trigger_update_average_ratings ON public.reviews;
    RAISE NOTICE '✅ Trigger "trigger_update_average_ratings" eliminado';
  ELSE
    RAISE NOTICE '⚠️  Trigger "trigger_update_average_ratings" no existe (ya eliminado)';
  END IF;
END $$;

-- ====================================
-- PASO 2: Eliminar función rota
-- ====================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'update_average_ratings'
  ) THEN
    DROP FUNCTION public.update_average_ratings() CASCADE;
    RAISE NOTICE '✅ Función "update_average_ratings()" eliminada';
  ELSE
    RAISE NOTICE '⚠️  Función "update_average_ratings()" no existe (ya eliminada)';
  END IF;
END $$;

-- ====================================
-- PASO 3: Verificar que submit_review no tiene lógica de actualización
-- ====================================

DO $$
DECLARE
  v_func_source text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_func_source
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'submit_review'
  LIMIT 1;

  IF v_func_source ILIKE '%UPDATE%users%total_reviews%' THEN
    RAISE WARNING '⚠️  ADVERTENCIA: submit_review() todavía tiene código que actualiza users.total_reviews. Revisar manualmente.';
  ELSE
    RAISE NOTICE '✅ Función "submit_review()" NO actualiza users.total_reviews (correcto)';
  END IF;
END $$;

-- ====================================
-- PASO 4: Información final
-- ====================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ FIX COMPLETADO';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE '📋 CAMBIOS REALIZADOS:';
  RAISE NOTICE '  1. ✅ Eliminado trigger "update_reviews_on_insert"';
  RAISE NOTICE '  2. ✅ Eliminada función "update_average_ratings()"';
  RAISE NOTICE '';
  RAISE NOTICE '📊 ESTADO DE COLUMNAS (INTACTAS):';
  RAISE NOTICE '  - client_profiles.total_reviews ✅ (existe, puede usarse para caché)';
  RAISE NOTICE '  - client_profiles.average_rating ✅ (existe, puede usarse para caché)';
  RAISE NOTICE '  - restaurants.total_reviews ✅ (existe, puede usarse para caché)';
  RAISE NOTICE '  - restaurants.average_rating ✅ (existe, puede usarse para caché)';
  RAISE NOTICE '  - delivery_agent_profiles ⚠️  (NO tiene total_reviews/average_rating)';
  RAISE NOTICE '';
  RAISE NOTICE '⚠️  IMPORTANTE:';
  RAISE NOTICE '  Los valores actuales en total_reviews/average_rating NO se actualizarán automáticamente.';
  RAISE NOTICE '  Opciones:';
  RAISE NOTICE '    A) Calcular dinámicamente desde reviews (RECOMENDADO)';
  RAISE NOTICE '    B) Crear cron job para actualizar periódicamente';
  RAISE NOTICE '    C) Crear trigger nuevo que actualice client_profiles/restaurants (ver PLAN)';
  RAISE NOTICE '';
  RAISE NOTICE '🚀 SIGUIENTE PASO:';
  RAISE NOTICE '  Prueba crear un review desde Flutter. Ya NO debe fallar.';
  RAISE NOTICE '';
END $$;
