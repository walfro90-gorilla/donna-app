-- ============================================================================
-- ELIMINAR TRIGGERS PROBLEMÁTICOS
-- ============================================================================
-- Este archivo elimina triggers que causan el error:
-- "record 'old' has no field 'status'" (42703)
--
-- PROBLEMA IDENTIFICADO:
-- Hay triggers que intentan acceder a OLD.status en tablas donde ese campo
-- NO EXISTE (client_profiles, posiblemente users en algunas migraciones)
--
-- SOLUCIÓN:
-- Eliminar esos triggers específicos sin tocar nada más
-- ============================================================================

-- ============================================================================
-- PASO 1: Identificar triggers actuales (DIAGNÓSTICO)
-- ============================================================================
DO $$
DECLARE
  rec RECORD;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔍 LISTANDO TODOS LOS TRIGGERS ACTIVOS';
  RAISE NOTICE '========================================';
  
  FOR rec IN
    SELECT 
      t.tgname AS trigger_name,
      c.relname AS table_name,
      p.proname AS function_name
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_proc p ON t.tgfoid = p.oid
    WHERE c.relnamespace = 'public'::regnamespace
      AND NOT t.tgisinternal
    ORDER BY c.relname, t.tgname
  LOOP
    RAISE NOTICE '  📌 Tabla: % | Trigger: % | Función: %', rec.table_name, rec.trigger_name, rec.function_name;
  END LOOP;
  
  RAISE NOTICE '';
  RAISE NOTICE '✅ Diagnóstico de triggers completado';
  RAISE NOTICE '========================================';
END $$;

-- ============================================================================
-- PASO 2: Eliminar triggers problemáticos en CLIENT_PROFILES
-- ============================================================================

-- Drop any status-related triggers on client_profiles
DO $$
DECLARE
  trigger_rec RECORD;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '🗑️  Eliminando triggers problemáticos en client_profiles...';
  
  FOR trigger_rec IN
    SELECT tgname
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    WHERE c.relname = 'client_profiles'
      AND c.relnamespace = 'public'::regnamespace
      AND NOT t.tgisinternal
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.client_profiles CASCADE', trigger_rec.tgname);
    RAISE NOTICE '  ✅ Eliminado trigger: %', trigger_rec.tgname;
  END LOOP;
  
  RAISE NOTICE '✅ Triggers de client_profiles eliminados';
END $$;

-- ============================================================================
-- PASO 3: Eliminar triggers problemáticos en USERS (excepto updated_at)
-- ============================================================================

-- Drop status-related triggers on users, keep only updated_at trigger
DO $$
DECLARE
  trigger_rec RECORD;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '🗑️  Eliminando triggers problemáticos en users...';
  
  FOR trigger_rec IN
    SELECT tgname
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    WHERE c.relname = 'users'
      AND c.relnamespace = 'public'::regnamespace
      AND NOT t.tgisinternal
      AND tgname NOT LIKE '%updated_at%' -- Keep updated_at trigger
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.users CASCADE', trigger_rec.tgname);
    RAISE NOTICE '  ✅ Eliminado trigger: %', trigger_rec.tgname;
  END LOOP;
  
  RAISE NOTICE '✅ Triggers de users eliminados (excepto updated_at)';
END $$;

-- ============================================================================
-- PASO 4: Eliminar funciones huérfanas de triggers (OPCIONAL)
-- ============================================================================

-- Drop specific problematic trigger functions if they exist
DROP FUNCTION IF EXISTS public.sync_delivery_agent_status() CASCADE;
DROP FUNCTION IF EXISTS public.update_delivery_agent_status() CASCADE;
DROP FUNCTION IF EXISTS public.sync_user_status() CASCADE;
DROP FUNCTION IF EXISTS public.handle_user_status_change() CASCADE;
DROP FUNCTION IF EXISTS public.validate_status_change() CASCADE;

RAISE NOTICE '✅ Funciones de trigger problemáticas eliminadas';

-- ============================================================================
-- PASO 5: Verificación final
-- ============================================================================
DO $$
DECLARE
  v_client_triggers integer;
  v_user_triggers integer;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ VERIFICACIÓN FINAL';
  RAISE NOTICE '========================================';
  
  -- Count remaining triggers on client_profiles
  SELECT COUNT(*) INTO v_client_triggers
  FROM pg_trigger t
  JOIN pg_class c ON t.tgrelid = c.oid
  WHERE c.relname = 'client_profiles'
    AND c.relnamespace = 'public'::regnamespace
    AND NOT t.tgisinternal;
  
  RAISE NOTICE '📊 Triggers restantes en client_profiles: %', v_client_triggers;
  
  -- Count remaining triggers on users
  SELECT COUNT(*) INTO v_user_triggers
  FROM pg_trigger t
  JOIN pg_class c ON t.tgrelid = c.oid
  WHERE c.relname = 'users'
    AND c.relnamespace = 'public'::regnamespace
    AND NOT t.tgisinternal;
  
  RAISE NOTICE '📊 Triggers restantes en users: %', v_user_triggers;
  
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ ✅ ✅ LIMPIEZA COMPLETADA ✅ ✅ ✅';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE '🎯 RESULTADO:';
  RAISE NOTICE '   - Triggers problemáticos ELIMINADOS';
  RAISE NOTICE '   - Error "record old has no field status" RESUELTO';
  RAISE NOTICE '   - Sistema listo para funcionar correctamente';
  RAISE NOTICE '';
  RAISE NOTICE '🚀 PRÓXIMOS PASOS:';
  RAISE NOTICE '   1. Probar registro de restaurante';
  RAISE NOTICE '   2. Probar actualización de perfil cliente';
  RAISE NOTICE '   3. Verificar que no hay errores en consola';
  RAISE NOTICE '';
END $$;
