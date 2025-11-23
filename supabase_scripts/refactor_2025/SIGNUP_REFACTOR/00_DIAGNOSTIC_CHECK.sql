-- ============================================================================
-- DIAGNÓSTICO COMPLETO - ¿Por qué la función sigue insertando 'client'?
-- ============================================================================

DO $$
DECLARE
  v_function_body TEXT;
  v_function_count INT;
  v_trigger_exists BOOLEAN;
  v_trigger_function TEXT;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔍 DIAGNÓSTICO COMPLETO';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  
  -- ========================================================================
  -- 1. Verificar cuántas versiones de master_handle_signup() existen
  -- ========================================================================
  
  SELECT COUNT(*) INTO v_function_count
  FROM pg_proc
  WHERE proname = 'master_handle_signup';
  
  RAISE NOTICE '📋 1. VERSIONES DE LA FUNCIÓN:';
  RAISE NOTICE '   Total de versiones: %', v_function_count;
  
  IF v_function_count = 0 THEN
    RAISE EXCEPTION '❌ NO EXISTE la función master_handle_signup()';
  ELSIF v_function_count > 1 THEN
    RAISE NOTICE '   ⚠️  ADVERTENCIA: Existen % versiones (debería ser solo 1)', v_function_count;
  ELSE
    RAISE NOTICE '   ✅ Solo existe 1 versión';
  END IF;
  
  RAISE NOTICE '';
  
  -- ========================================================================
  -- 2. Verificar el cuerpo de la función
  -- ========================================================================
  
  SELECT pg_get_functiondef(oid) INTO v_function_body
  FROM pg_proc
  WHERE proname = 'master_handle_signup'
    AND pronamespace = 'public'::regnamespace
  LIMIT 1;
  
  RAISE NOTICE '📋 2. CONTENIDO DE LA FUNCIÓN:';
  
  -- Verificar normalización
  IF v_function_body LIKE '%WHEN ''client'' THEN ''cliente''%' THEN
    RAISE NOTICE '   ✅ Tiene normalización: client -> cliente';
  ELSE
    RAISE NOTICE '   ❌ NO tiene normalización: client -> cliente';
    RAISE NOTICE '   🚨 LA FUNCIÓN ESTÁ MAL';
  END IF;
  
  IF v_function_body LIKE '%WHEN ''restaurant'' THEN ''restaurante''%' THEN
    RAISE NOTICE '   ✅ Tiene normalización: restaurant -> restaurante';
  ELSE
    RAISE NOTICE '   ❌ NO tiene normalización: restaurant -> restaurante';
  END IF;
  
  IF v_function_body LIKE '%WHEN ''delivery_agent'' THEN ''repartidor''%' THEN
    RAISE NOTICE '   ✅ Tiene normalización: delivery_agent -> repartidor';
  ELSE
    RAISE NOTICE '   ❌ NO tiene normalización: delivery_agent -> repartidor';
  END IF;
  
  RAISE NOTICE '';
  
  -- ========================================================================
  -- 3. Verificar el trigger
  -- ========================================================================
  
  SELECT EXISTS(
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE t.tgname = 'master_handle_new_user'
      AND c.relname = 'users'
      AND c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'auth')
  ) INTO v_trigger_exists;
  
  RAISE NOTICE '📋 3. TRIGGER:';
  
  IF v_trigger_exists THEN
    RAISE NOTICE '   ✅ El trigger master_handle_new_user EXISTE en auth.users';
    
    -- Verificar qué función ejecuta el trigger
    SELECT p.proname INTO v_trigger_function
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE t.tgname = 'master_handle_new_user'
      AND c.relname = 'users'
      AND c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'auth');
    
    RAISE NOTICE '   Función ejecutada: %', v_trigger_function;
    
    IF v_trigger_function = 'master_handle_signup' THEN
      RAISE NOTICE '   ✅ El trigger apunta a master_handle_signup()';
    ELSE
      RAISE NOTICE '   ❌ El trigger apunta a OTRA función: %', v_trigger_function;
    END IF;
    
  ELSE
    RAISE NOTICE '   ❌ El trigger NO EXISTE';
  END IF;
  
  RAISE NOTICE '';
  
  -- ========================================================================
  -- 4. Mostrar la sección relevante del código de la función
  -- ========================================================================
  
  RAISE NOTICE '📋 4. FRAGMENTO DEL CÓDIGO (normalización de roles):';
  RAISE NOTICE '';
  
  -- Extraer la sección de normalización
  IF v_function_body ~ 'CASE lower\(v_role\)' THEN
    RAISE NOTICE '   Se encontró el bloque CASE lower(v_role)';
    RAISE NOTICE '   Ver el código completo ejecutando:';
    RAISE NOTICE '   SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = ''master_handle_signup'';';
  ELSE
    RAISE NOTICE '   ⚠️  NO se encontró el bloque CASE lower(v_role)';
  END IF;
  
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ DIAGNÓSTICO COMPLETADO';
  RAISE NOTICE '========================================';
  
END $$;

-- ============================================================================
-- MOSTRAR EL CÓDIGO COMPLETO DE LA FUNCIÓN PARA INSPECCIÓN MANUAL
-- ============================================================================

SELECT 
  '🔍 CÓDIGO COMPLETO DE master_handle_signup():' as info,
  pg_get_functiondef(oid) as function_definition
FROM pg_proc
WHERE proname = 'master_handle_signup'
  AND pronamespace = 'public'::regnamespace
LIMIT 1;
