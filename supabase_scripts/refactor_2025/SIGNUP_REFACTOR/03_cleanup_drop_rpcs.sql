-- ============================================================================
-- FASE 1 - SCRIPT 03: ELIMINAR RPCs OBSOLETOS
-- ============================================================================
-- Descripción: Elimina funciones públicas redundantes que NO deben ser
--              llamadas desde Flutter. El signup debe ser automático vía
--              el trigger en auth.users, no mediante RPCs manuales.
-- ============================================================================

-- ============================================================================
-- HELPER: ELIMINAR TODAS LAS SOBRECARGAS DE UNA FUNCIÓN
-- ============================================================================

DO $$
DECLARE
  v_func_record RECORD;
  v_drop_sql TEXT;
  v_count INT := 0;
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '🗑️  ELIMINANDO RPCs OBSOLETOS DE SIGNUP';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';

  -- ============================================================================
  -- ELIMINAR TODAS LAS VERSIONES DE FUNCIONES OBSOLETAS
  -- ============================================================================
  
  FOR v_func_record IN
    SELECT 
      n.nspname AS schema_name,
      p.proname AS function_name,
      pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        -- RPCs de registro obsoletos
        'register_client',
        'register_delivery_agent',
        'register_delivery_agent_atomic',
        'register_restaurant',
        'register_restaurant_v2',
        
        -- Helpers de creación obsoletos
        'create_user_profile_public',
        'create_delivery_agent',
        'create_restaurant_public',
        
        -- Helpers de ensure obsoletos
        'ensure_user_profile_public',
        'ensure_user_profile_v2',
        'ensure_client_profile_and_account',
        'ensure_delivery_agent_role_and_profile',
        'ensure_my_delivery_profile',
        
        -- Triggers helpers obsoletos
        '_trg_call_ensure_client_profile_and_account',
        '_trg_handle_client_account_insert',
        '_should_autocreate_client',
        'create_auth_user_profile'
      )
    ORDER BY p.proname, p.oid
  LOOP
    -- Construir el DROP con la firma completa
    v_drop_sql := format(
      'DROP FUNCTION IF EXISTS %I.%I(%s) CASCADE',
      v_func_record.schema_name,
      v_func_record.function_name,
      v_func_record.args
    );
    
    -- Ejecutar el DROP
    EXECUTE v_drop_sql;
    
    -- Log
    RAISE NOTICE '✅ Eliminado: %.%(%)', 
      v_func_record.schema_name, 
      v_func_record.function_name,
      v_func_record.args;
    
    v_count := v_count + 1;
  END LOOP;

  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ TOTAL DE FUNCIONES ELIMINADAS: %', v_count;
  RAISE NOTICE '========================================';
END $$;

-- ============================================================================
-- VERIFICACIÓN FINAL
-- ============================================================================

DO $$
DECLARE
  v_remaining_signup_rpcs INT;
BEGIN
  -- Contar funciones que aún contienen 'register' o 'ensure' en su nombre
  SELECT COUNT(*) INTO v_remaining_signup_rpcs
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND (
      p.proname ILIKE '%register%'
      OR p.proname ILIKE '%ensure%profile%'
      OR p.proname ILIKE '%create_user%'
      OR p.proname ILIKE '%create_delivery_agent%'
      OR p.proname ILIKE '%create_restaurant%'
    )
    AND p.proname NOT IN (
      -- Excepciones: funciones que SÍ deben existir
      'repair_user_registration_misclassification',
      'update_restaurant_completion_trigger',
      'ensure_account', -- puede ser útil internamente
      'ensure_financial_account', -- puede ser útil internamente
      'ensure_user_preferences' -- puede ser útil internamente
    );
  
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '📊 VERIFICACIÓN POST-LIMPIEZA';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'RPCs de signup restantes (posibles duplicados): %', v_remaining_signup_rpcs;
  RAISE NOTICE '';
  
  IF v_remaining_signup_rpcs > 0 THEN
    RAISE NOTICE '⚠️  Aún existen % funciones con nombres similares.', v_remaining_signup_rpcs;
    RAISE NOTICE 'Ejecuta este query para verlas:';
    RAISE NOTICE '';
    RAISE NOTICE 'SELECT proname, pg_get_function_identity_arguments(oid) as args';
    RAISE NOTICE 'FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace';
    RAISE NOTICE 'WHERE n.nspname = ''public''';
    RAISE NOTICE '  AND (proname ILIKE ''%%register%%'' OR proname ILIKE ''%%ensure%%profile%%'');';
    RAISE NOTICE '';
  ELSE
    RAISE NOTICE '✅ No quedan funciones de signup obsoletas.';
    RAISE NOTICE '';
  END IF;
  
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ FASE 1 - SCRIPT 03 COMPLETADO';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE '📋 Resumen de Fase 1:';
  RAISE NOTICE '   ✅ Backup de funciones obsoletas: completado (script 01)';
  RAISE NOTICE '   ✅ Triggers conflictivos desactivados: completado (script 02)';
  RAISE NOTICE '   ✅ RPCs obsoletos eliminados: completado (script 03) ← ACTUAL';
  RAISE NOTICE '';
  RAISE NOTICE '🚀 Puedes continuar con FASE 2:';
  RAISE NOTICE '   04_implementation_master_function.sql';
  RAISE NOTICE '';
END $$;

-- ============================================================================
-- MANTENER RPCs ÚTILES (DOCUMENTACIÓN)
-- ============================================================================

-- ✅ NO ELIMINAR: admin_approve_user()
--    Útil para que el admin apruebe usuarios manualmente.

-- ✅ NO ELIMINAR: admin_approve_delivery_agent()
--    Útil para que el admin apruebe repartidores.

-- ✅ NO ELIMINAR: admin_approve_restaurant()
--    Útil para que el admin apruebe restaurantes.

-- ✅ NO ELIMINAR: update_my_delivery_profile()
--    Útil para que repartidores actualicen su perfil.

-- ✅ NO ELIMINAR: check_email_availability()
--    Útil para validar emails antes de signup.

-- ✅ NO ELIMINAR: check_phone_availability()
--    Útil para validar teléfonos antes de signup.

-- ✅ NO ELIMINAR: check_restaurant_name_availability()
--    Útil para validar nombres de restaurantes.

-- ✅ NO ELIMINAR: normalize_user_role()
--    Útil para normalizar roles (client→cliente).
