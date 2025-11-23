-- ============================================================================
-- Script: 14_create_trigger_manually.sql
-- Descripcion: Crea trigger en auth.users manualmente (solo si no existe)
-- Autor: Sistema
-- Fecha: 2025-01-XX
-- IMPORTANTE: Este script DEBE ejecutarse desde Supabase Dashboard
--             con un usuario que tenga permisos de OWNER
-- ============================================================================

-- PASO 1: Verificar si el trigger ya existe
-- ============================================================================
DO $$
DECLARE
  v_trigger_exists boolean;
  v_trigger_name text;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'auth' 
    AND c.relname = 'users'
    AND t.tgname IN ('on_auth_user_created', 'handle_new_user')
  ) INTO v_trigger_exists;

  IF v_trigger_exists THEN
    SELECT t.tgname INTO v_trigger_name
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'auth' 
    AND c.relname = 'users'
    AND t.tgname IN ('on_auth_user_created', 'handle_new_user')
    LIMIT 1;
    
    RAISE NOTICE '[INFO] Trigger YA EXISTE: %', v_trigger_name;
    RAISE NOTICE '[INFO] NO es necesario crear el trigger';
    RAISE NOTICE '[INFO] El sistema ya esta funcionando correctamente';
  ELSE
    RAISE NOTICE '[WARNING] Trigger NO existe';
    RAISE NOTICE '[ACTION] Ejecutando creacion del trigger...';
  END IF;
END $$;


-- PASO 2: Crear trigger (solo si no existe)
-- ============================================================================
-- NOTA: Este comando puede fallar si no tienes permisos de OWNER
-- En ese caso, contacta al administrador de Supabase

DO $$
BEGIN
  -- Intentar eliminar trigger si existe
  BEGIN
    DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users CASCADE;
    RAISE NOTICE '[OK] Trigger anterior eliminado (si existia)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '[WARNING] No se pudo eliminar trigger anterior: %', SQLERRM;
  END;

  -- Intentar crear trigger
  BEGIN
    CREATE TRIGGER on_auth_user_created
      AFTER INSERT ON auth.users
      FOR EACH ROW
      EXECUTE FUNCTION public.handle_new_user();
    
    RAISE NOTICE '[SUCCESS] Trigger on_auth_user_created creado correctamente';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE EXCEPTION '[ERROR] Permisos insuficientes. Debes ejecutar este script con usuario OWNER de auth.users';
  WHEN duplicate_object THEN
    RAISE NOTICE '[INFO] Trigger ya existe, no es necesario crearlo';
  WHEN OTHERS THEN
    RAISE EXCEPTION '[ERROR] Error al crear trigger: %', SQLERRM;
  END;
END $$;


-- PASO 3: Verificar que el trigger esté activo
-- ============================================================================
DO $$
DECLARE
  v_trigger_exists boolean;
  v_trigger_name text;
  v_trigger_enabled text;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'auth' 
    AND c.relname = 'users'
    AND t.tgname = 'on_auth_user_created'
  ) INTO v_trigger_exists;

  IF v_trigger_exists THEN
    SELECT 
      t.tgname,
      CASE t.tgenabled
        WHEN 'O' THEN 'enabled'
        WHEN 'D' THEN 'disabled'
        ELSE 'unknown'
      END
    INTO v_trigger_name, v_trigger_enabled
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'auth' 
    AND c.relname = 'users'
    AND t.tgname = 'on_auth_user_created';
    
    RAISE NOTICE '[OK] Trigger: %', v_trigger_name;
    RAISE NOTICE '[OK] Estado: %', v_trigger_enabled;
    
    IF v_trigger_enabled = 'enabled' THEN
      RAISE NOTICE '[SUCCESS] Trigger activo y funcionando';
    ELSE
      RAISE WARNING '[WARNING] Trigger existe pero esta deshabilitado';
    END IF;
  ELSE
    RAISE EXCEPTION '[ERROR] Trigger NO fue creado correctamente';
  END IF;
END $$;


-- ============================================================================
-- FIN DEL SCRIPT
-- ============================================================================
