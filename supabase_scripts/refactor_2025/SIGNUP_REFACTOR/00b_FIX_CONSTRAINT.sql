-- ============================================================================
-- HOTFIX: VERIFICAR Y RECREAR EL CONSTRAINT users_role_check
-- ============================================================================
-- Descripción: El constraint está rechazando 'cliente' pero debería aceptarlo.
--              Este script verifica y recrea el constraint correctamente.
-- ============================================================================

-- ============================================================================
-- PASO 1: Verificar el constraint actual
-- ============================================================================

DO $$
DECLARE
  v_constraint_def TEXT;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔍 VERIFICANDO CONSTRAINT users_role_check';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  
  -- Obtener la definición del constraint
  SELECT pg_get_constraintdef(oid) INTO v_constraint_def
  FROM pg_constraint
  WHERE conname = 'users_role_check'
    AND conrelid = 'public.users'::regclass;
  
  IF v_constraint_def IS NULL THEN
    RAISE NOTICE '❌ El constraint users_role_check NO EXISTE';
  ELSE
    RAISE NOTICE '📋 Definición actual:';
    RAISE NOTICE '%', v_constraint_def;
    RAISE NOTICE '';
    
    -- Verificar si acepta los valores correctos
    IF v_constraint_def LIKE '%cliente%' THEN
      RAISE NOTICE '✅ Acepta: cliente';
    ELSE
      RAISE NOTICE '❌ NO acepta: cliente (ESTE ES EL PROBLEMA)';
    END IF;
    
    IF v_constraint_def LIKE '%restaurante%' THEN
      RAISE NOTICE '✅ Acepta: restaurante';
    ELSE
      RAISE NOTICE '❌ NO acepta: restaurante';
    END IF;
    
    IF v_constraint_def LIKE '%repartidor%' THEN
      RAISE NOTICE '✅ Acepta: repartidor';
    ELSE
      RAISE NOTICE '❌ NO acepta: repartidor';
    END IF;
    
    IF v_constraint_def LIKE '%admin%' THEN
      RAISE NOTICE '✅ Acepta: admin';
    ELSE
      RAISE NOTICE '❌ NO acepta: admin';
    END IF;
  END IF;
  
  RAISE NOTICE '';
  
END $$;

-- ============================================================================
-- PASO 2: Recrear el constraint con los valores correctos
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '🔧 Recreando constraint...';
  RAISE NOTICE '';
  
  -- Eliminar el constraint viejo
  ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check CASCADE;
  
  RAISE NOTICE '   ✅ Constraint viejo eliminado';
  
  -- Crear el constraint nuevo con valores EN ESPAÑOL
  ALTER TABLE public.users
  ADD CONSTRAINT users_role_check 
  CHECK (role IN ('cliente', 'restaurante', 'repartidor', 'admin'));
  
  RAISE NOTICE '   ✅ Constraint nuevo creado';
  RAISE NOTICE '';
  
END $$;

-- ============================================================================
-- PASO 3: Verificar que el constraint se creó correctamente
-- ============================================================================

DO $$
DECLARE
  v_constraint_def TEXT;
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ VERIFICACIÓN FINAL';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  
  -- Obtener la nueva definición
  SELECT pg_get_constraintdef(oid) INTO v_constraint_def
  FROM pg_constraint
  WHERE conname = 'users_role_check'
    AND conrelid = 'public.users'::regclass;
  
  RAISE NOTICE '📋 Nueva definición:';
  RAISE NOTICE '%', v_constraint_def;
  RAISE NOTICE '';
  
  -- Verificar que tenga los valores correctos
  IF v_constraint_def LIKE '%cliente%' AND 
     v_constraint_def LIKE '%restaurante%' AND 
     v_constraint_def LIKE '%repartidor%' AND 
     v_constraint_def LIKE '%admin%' THEN
    RAISE NOTICE '✅ CONSTRAINT CORRECTO';
    RAISE NOTICE '';
    RAISE NOTICE '🚀 Ahora puedes ejecutar: 07b_hotfix_verify_trigger.sql';
  ELSE
    RAISE EXCEPTION '❌ El constraint NO se creó correctamente';
  END IF;
  
  RAISE NOTICE '';
  
END $$;
