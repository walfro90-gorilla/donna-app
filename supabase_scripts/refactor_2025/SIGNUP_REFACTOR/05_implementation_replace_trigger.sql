-- ============================================================================
-- FASE 2 - SCRIPT 05: VERIFICAR Y CONFIGURAR TRIGGER EN auth.users
-- ============================================================================
-- ⚠️  ADVERTENCIA: Este script NO puede crear el trigger en auth.users
--     directamente porque requiere permisos de superusuario (postgres).
--
-- 📋 INSTRUCCIONES:
--     1. Lee el archivo: 05_MANUAL_TRIGGER_INSTRUCTIONS.md
--     2. Sigue las instrucciones para crear el trigger manualmente
--     3. Vuelve aquí y ejecuta este script para verificar
-- ============================================================================

-- ============================================================================
-- PASO 1: VERIFICAR SI EL TRIGGER YA EXISTE
-- ============================================================================

DO $$
DECLARE
  v_trigger_exists BOOLEAN;
  v_trigger_function_name TEXT;
  v_trigger_enabled CHAR;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔍 VERIFICANDO TRIGGER EN auth.users';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';

  -- Verificar que el trigger existe
  SELECT 
    TRUE,
    p.proname,
    t.tgenabled
  INTO 
    v_trigger_exists,
    v_trigger_function_name,
    v_trigger_enabled
  FROM pg_trigger t
  JOIN pg_proc p ON p.oid = t.tgfoid
  WHERE t.tgname = 'on_auth_user_created'
    AND t.tgrelid = 'auth.users'::regclass;

  IF v_trigger_exists THEN
    RAISE NOTICE '✅ TRIGGER ENCONTRADO';
    RAISE NOTICE '';
    RAISE NOTICE 'Nombre: on_auth_user_created';
    RAISE NOTICE 'Tabla: auth.users';
    RAISE NOTICE 'Función: public.%', v_trigger_function_name;
    RAISE NOTICE 'Estado: %', CASE 
      WHEN v_trigger_enabled = 'O' THEN 'HABILITADO ✅'
      WHEN v_trigger_enabled = 'D' THEN 'DESHABILITADO ⚠️'
      ELSE 'DESCONOCIDO ❌'
    END;
    RAISE NOTICE '';
    
    IF v_trigger_function_name = 'master_handle_signup' THEN
      RAISE NOTICE '✅ El trigger apunta a la función correcta: master_handle_signup()';
      RAISE NOTICE '';
      
      IF v_trigger_enabled = 'O' THEN
        RAISE NOTICE '========================================';
        RAISE NOTICE '✅ CONFIGURACIÓN CORRECTA';
        RAISE NOTICE '========================================';
        RAISE NOTICE '';
        RAISE NOTICE '🚀 Puedes continuar con:';
        RAISE NOTICE '   - Limpieza de funciones obsoletas (abajo)';
        RAISE NOTICE '   - FASE 3: 06_implementation_grant_permissions.sql';
      ELSE
        RAISE WARNING '⚠️  El trigger existe pero está DESHABILITADO';
        RAISE WARNING 'Ejecuta: ALTER TABLE auth.users ENABLE TRIGGER on_auth_user_created;';
      END IF;
    ELSE
      RAISE WARNING '⚠️  El trigger existe pero apunta a: %', v_trigger_function_name;
      RAISE WARNING 'Se esperaba: master_handle_signup';
      RAISE WARNING 'Sigue las instrucciones en: 05_MANUAL_TRIGGER_INSTRUCTIONS.md';
    END IF;
  ELSE
    RAISE WARNING '';
    RAISE WARNING '========================================';
    RAISE WARNING '⚠️  TRIGGER NO ENCONTRADO';
    RAISE WARNING '========================================';
    RAISE WARNING '';
    RAISE WARNING 'El trigger "on_auth_user_created" NO existe en auth.users';
    RAISE WARNING '';
    RAISE WARNING '📋 ACCIÓN REQUERIDA:';
    RAISE WARNING '   1. Abre el archivo: 05_MANUAL_TRIGGER_INSTRUCTIONS.md';
    RAISE WARNING '   2. Sigue las instrucciones para crear el trigger';
    RAISE WARNING '   3. Vuelve a ejecutar este script para verificar';
    RAISE WARNING '';
    RAISE WARNING '💡 TIP: El trigger debe ejecutar public.master_handle_signup()';
    RAISE WARNING '';
  END IF;
END $$;

-- ============================================================================
-- PASO 2: LIMPIAR FUNCIONES OBSOLETAS (Solo si el trigger está OK)
-- ============================================================================

DO $$
DECLARE
  v_trigger_ok BOOLEAN;
  v_functions_dropped INT := 0;
BEGIN
  -- Verificar que el trigger existe y apunta a master_handle_signup
  SELECT 
    CASE 
      WHEN p.proname = 'master_handle_signup' AND t.tgenabled = 'O' THEN TRUE
      ELSE FALSE
    END
  INTO v_trigger_ok
  FROM pg_trigger t
  JOIN pg_proc p ON p.oid = t.tgfoid
  WHERE t.tgname = 'on_auth_user_created'
    AND t.tgrelid = 'auth.users'::regclass;

  IF v_trigger_ok THEN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🗑️  LIMPIANDO FUNCIONES OBSOLETAS';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Eliminar funciones trigger obsoletas
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'handle_new_user') THEN
      DROP FUNCTION IF EXISTS public.handle_new_user CASCADE;
      RAISE NOTICE '✅ Eliminado: handle_new_user()';
      v_functions_dropped := v_functions_dropped + 1;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = '_trg_after_insert_auth_user') THEN
      DROP FUNCTION IF EXISTS public._trg_after_insert_auth_user CASCADE;
      RAISE NOTICE '✅ Eliminado: _trg_after_insert_auth_user()';
      v_functions_dropped := v_functions_dropped + 1;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'create_public_user_on_signup') THEN
      DROP FUNCTION IF EXISTS public.create_public_user_on_signup CASCADE;
      RAISE NOTICE '✅ Eliminado: create_public_user_on_signup()';
      v_functions_dropped := v_functions_dropped + 1;
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE 'Total de funciones eliminadas: %', v_functions_dropped;
    
    IF v_functions_dropped = 0 THEN
      RAISE NOTICE '(No había funciones obsoletas)';
    END IF;
  ELSE
    RAISE NOTICE '';
    RAISE NOTICE '⚠️  Saltando limpieza de funciones (el trigger no está configurado correctamente)';
  END IF;
END $$;

-- ============================================================================
-- PASO 3: RESUMEN FINAL
-- ============================================================================

DO $$
DECLARE
  v_trigger_ok BOOLEAN;
  v_function_name TEXT;
BEGIN
  SELECT 
    CASE 
      WHEN p.proname = 'master_handle_signup' AND t.tgenabled = 'O' THEN TRUE
      ELSE FALSE
    END,
    p.proname
  INTO v_trigger_ok, v_function_name
  FROM pg_trigger t
  JOIN pg_proc p ON p.oid = t.tgfoid
  WHERE t.tgname = 'on_auth_user_created'
    AND t.tgrelid = 'auth.users'::regclass;

  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  
  IF v_trigger_ok THEN
    RAISE NOTICE '✅ FASE 2 - SCRIPT 05 COMPLETADO';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Resumen:';
    RAISE NOTICE '   ✅ Trigger verificado: on_auth_user_created';
    RAISE NOTICE '   ✅ Función correcta: master_handle_signup()';
    RAISE NOTICE '   ✅ Funciones obsoletas eliminadas';
    RAISE NOTICE '';
    RAISE NOTICE '🚀 Continúa con FASE 3:';
    RAISE NOTICE '   06_implementation_grant_permissions.sql';
  ELSE
    RAISE NOTICE '⚠️  FASE 2 - SCRIPT 05 INCOMPLETO';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '❌ El trigger NO está configurado correctamente';
    RAISE NOTICE '';
    RAISE NOTICE '📋 ACCIÓN REQUERIDA:';
    RAISE NOTICE '   1. Lee: 05_MANUAL_TRIGGER_INSTRUCTIONS.md';
    RAISE NOTICE '   2. Crea el trigger manualmente';
    RAISE NOTICE '   3. Vuelve a ejecutar este script';
    RAISE NOTICE '';
    
    IF v_function_name IS NOT NULL THEN
      RAISE NOTICE '⚠️  Función actual del trigger: %', v_function_name;
      RAISE NOTICE '   (Se esperaba: master_handle_signup)';
    ELSE
      RAISE NOTICE '❌ El trigger no existe en auth.users';
    END IF;
  END IF;
  
  RAISE NOTICE '';
END $$;

-- ============================================================================
-- INFORMACIÓN ADICIONAL
-- ============================================================================

-- Para ver todos los triggers en auth.users:
-- SELECT t.tgname, p.proname, t.tgenabled 
-- FROM pg_trigger t 
-- JOIN pg_proc p ON p.oid = t.tgfoid 
-- WHERE t.tgrelid = 'auth.users'::regclass;

-- Para ver la definición completa del trigger:
-- SELECT pg_get_triggerdef(oid) FROM pg_trigger 
-- WHERE tgname = 'on_auth_user_created' AND tgrelid = 'auth.users'::regclass;
