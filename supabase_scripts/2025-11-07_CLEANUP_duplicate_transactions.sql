-- =====================================================================
-- 🧹 LIMPIEZA DE TRANSACCIONES DUPLICADAS
-- =====================================================================
-- PROPÓSITO:
--   Eliminar registros duplicados en account_transactions que violan
--   el constraint único: (order_id, account_id, type)
--
-- ESTRATEGIA:
--   1. Identificar grupos de duplicados
--   2. Mantener el registro MÁS RECIENTE de cada grupo
--   3. Eliminar los registros antiguos
--   4. Verificar integridad final
-- =====================================================================

DO $$
DECLARE
  v_duplicates_found integer := 0;
  v_duplicates_deleted integer := 0;
BEGIN
  RAISE NOTICE '🔍 Buscando transacciones duplicadas...';
  
  -- Contar duplicados
  SELECT COUNT(*) INTO v_duplicates_found
  FROM (
    SELECT order_id, account_id, type, COUNT(*) as cnt
    FROM public.account_transactions
    WHERE order_id IS NOT NULL
    GROUP BY order_id, account_id, type
    HAVING COUNT(*) > 1
  ) duplicates;
  
  IF v_duplicates_found = 0 THEN
    RAISE NOTICE '✅ No se encontraron duplicados. Base de datos limpia.';
  ELSE
    RAISE NOTICE '⚠️  Se encontraron % grupos de registros duplicados', v_duplicates_found;
    RAISE NOTICE '🗑️  Eliminando duplicados (manteniendo el más reciente)...';
    
    -- Eliminar duplicados (mantener el más reciente por created_at)
    WITH duplicates_to_delete AS (
      SELECT id
      FROM (
        SELECT 
          id,
          ROW_NUMBER() OVER (
            PARTITION BY order_id, account_id, type 
            ORDER BY created_at DESC, id DESC
          ) as rn
        FROM public.account_transactions
        WHERE order_id IS NOT NULL
      ) ranked
      WHERE rn > 1
    )
    DELETE FROM public.account_transactions
    WHERE id IN (SELECT id FROM duplicates_to_delete);
    
    GET DIAGNOSTICS v_duplicates_deleted = ROW_COUNT;
    
    RAISE NOTICE '✅ Se eliminaron % registros duplicados', v_duplicates_deleted;
  END IF;
  
  -- Verificación final
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ LIMPIEZA COMPLETADA';
  RAISE NOTICE '========================================';
  RAISE NOTICE '📊 Duplicados encontrados: %', v_duplicates_found;
  RAISE NOTICE '🗑️  Registros eliminados: %', v_duplicates_deleted;
  RAISE NOTICE '========================================';
  RAISE NOTICE '📝 Próximo paso:';
  RAISE NOTICE '  Prueba marcar una orden como delivered';
  RAISE NOTICE '  El trigger v3 ahora funcionará correctamente';
  RAISE NOTICE '========================================';
END $$;

-- ==========================================
-- VERIFICACIÓN DE INTEGRIDAD
-- ==========================================
DO $$
DECLARE
  v_remaining_duplicates integer;
BEGIN
  -- Verificar que NO quedan duplicados
  SELECT COUNT(*) INTO v_remaining_duplicates
  FROM (
    SELECT order_id, account_id, type, COUNT(*) as cnt
    FROM public.account_transactions
    WHERE order_id IS NOT NULL
    GROUP BY order_id, account_id, type
    HAVING COUNT(*) > 1
  ) remaining;
  
  IF v_remaining_duplicates > 0 THEN
    RAISE WARNING '⚠️  ADVERTENCIA: Aún quedan % grupos duplicados', v_remaining_duplicates;
  ELSE
    RAISE NOTICE '✅ Verificación exitosa: No quedan duplicados';
  END IF;
END $$;
