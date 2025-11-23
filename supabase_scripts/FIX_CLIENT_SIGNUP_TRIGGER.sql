-- ============================================================================
-- FIX_CLIENT_SIGNUP_TRIGGER.sql
-- ============================================================================
-- OBJETIVO: Reparar el registro de clientes creando el trigger faltante
-- PROBLEMA: auth.users NO tiene trigger, por lo que handle_new_user_signup_v2()
--           nunca se ejecuta y los datos quedan vacíos
-- ============================================================================

-- ============================================================================
-- PARTE 1: ELIMINAR FUNCIONES DUPLICADAS DE ensure_user_profile_public()
-- ============================================================================
-- Hay 3 versiones con firmas diferentes que causan confusión.
-- Solo necesitamos handle_new_user_signup_v2(), así que limpiamos.
-- ============================================================================

DO $$
BEGIN
  -- Eliminar versión con 5 parámetros (p_user_id, p_email, p_role, p_name, p_phone)
  IF EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'ensure_user_profile_public' 
    AND pg_get_function_arguments(oid) = 'p_user_id uuid, p_email text, p_role text, p_name text DEFAULT NULL::text, p_phone text DEFAULT NULL::text'
  ) THEN
    DROP FUNCTION public.ensure_user_profile_public(uuid, text, text, text, text);
    RAISE NOTICE '✅ Eliminada ensure_user_profile_public(5 params)';
  END IF;

  -- Eliminar versión con 9 parámetros (versión extendida con ubicación)
  IF EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'ensure_user_profile_public' 
    AND pg_get_function_arguments(oid) LIKE '%p_address_structured%'
  ) THEN
    DROP FUNCTION IF EXISTS public.ensure_user_profile_public(uuid, text, text, text, text, text, double precision, double precision, jsonb);
    RAISE NOTICE '✅ Eliminada ensure_user_profile_public(9 params)';
  END IF;

  -- Eliminar versión wrapper que llama a la función anterior
  IF EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'create_user_profile_public'
  ) THEN
    DROP FUNCTION IF EXISTS public.create_user_profile_public(uuid, text, text, text, text, text, double precision, double precision, jsonb, boolean);
    RAISE NOTICE '✅ Eliminada create_user_profile_public() wrapper';
  END IF;

END $$;


-- ============================================================================
-- PARTE 2: VERIFICAR QUE handle_new_user_signup_v2() EXISTE
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'handle_new_user_signup_v2'
    AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  ) THEN
    RAISE EXCEPTION '❌ FATAL: handle_new_user_signup_v2() NO EXISTE. Debe ejecutarse primero el script que la crea.';
  ELSE
    RAISE NOTICE '✅ handle_new_user_signup_v2() existe y está lista';
  END IF;
END $$;


-- ============================================================================
-- PARTE 3: CREAR EL TRIGGER FALTANTE EN auth.users
-- ============================================================================
-- Este es el fix principal: conectar auth.users con handle_new_user_signup_v2()
-- ============================================================================

-- 3.1 Eliminar trigger si existe (para recrearlo limpio)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- 3.2 Crear el trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user_signup_v2();

-- Log de confirmación
DO $$
BEGIN
  RAISE NOTICE '✅✅✅ TRIGGER on_auth_user_created CREADO EXITOSAMENTE ✅✅✅';
  RAISE NOTICE '   - Tabla: auth.users';
  RAISE NOTICE '   - Evento: AFTER INSERT';
  RAISE NOTICE '   - Función: public.handle_new_user_signup_v2()';
  RAISE NOTICE '';
  RAISE NOTICE '🎯 AHORA CUANDO UN USUARIO SE REGISTRE:';
  RAISE NOTICE '   1. Supabase Auth crea el usuario en auth.users';
  RAISE NOTICE '   2. Trigger ejecuta handle_new_user_signup_v2()';
  RAISE NOTICE '   3. Se copian name, phone, lat, lon desde raw_user_meta_data';
  RAISE NOTICE '   4. Se crea client_profiles con ubicación';
  RAISE NOTICE '   5. Se crea user_preferences';
  RAISE NOTICE '   6. Se crea accounts';
  RAISE NOTICE '   7. Todo queda registrado en debug_user_signup_log';
  RAISE NOTICE '';
  RAISE NOTICE '✨ EL PROBLEMA ESTÁ SOLUCIONADO ✨';
END $$;


-- ============================================================================
-- PARTE 4: VERIFICACIÓN FINAL
-- ============================================================================

DO $$
DECLARE
  v_trigger_exists boolean;
  v_function_exists boolean;
BEGIN
  -- Verificar que el trigger existe
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE t.tgname = 'on_auth_user_created'
    AND n.nspname = 'auth'
    AND c.relname = 'users'
  ) INTO v_trigger_exists;

  -- Verificar que la función existe
  SELECT EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'handle_new_user_signup_v2'
    AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  ) INTO v_function_exists;

  IF v_trigger_exists AND v_function_exists THEN
    RAISE NOTICE '';
    RAISE NOTICE '================================================';
    RAISE NOTICE '✅ VERIFICACIÓN EXITOSA';
    RAISE NOTICE '================================================';
    RAISE NOTICE '✅ Trigger: on_auth_user_created EXISTS';
    RAISE NOTICE '✅ Función: handle_new_user_signup_v2() EXISTS';
    RAISE NOTICE '✅ Conexión: auth.users → handle_new_user_signup_v2()';
    RAISE NOTICE '';
    RAISE NOTICE '🎉 TODO LISTO PARA PROBAR 🎉';
    RAISE NOTICE '';
    RAISE NOTICE '📋 PRÓXIMO PASO:';
    RAISE NOTICE '   Crear un nuevo cliente desde Flutter y verificar';
    RAISE NOTICE '   que name, phone, lat, lon se guardan correctamente';
    RAISE NOTICE '================================================';
  ELSE
    IF NOT v_trigger_exists THEN
      RAISE EXCEPTION '❌ ERROR: Trigger on_auth_user_created NO fue creado';
    END IF;
    IF NOT v_function_exists THEN
      RAISE EXCEPTION '❌ ERROR: Función handle_new_user_signup_v2() NO existe';
    END IF;
  END IF;
END $$;


-- ============================================================================
-- FIN DEL SCRIPT
-- ============================================================================
-- SIGUIENTE PASO: Crear un nuevo cliente y verificar con estas queries:
--
-- 1. Ver usuario creado:
--    SELECT id, email, name, phone, role 
--    FROM public.users 
--    WHERE email = 'tu_email@test.com';
--
-- 2. Ver perfil con ubicación:
--    SELECT user_id, lat, lon, address, address_structured
--    FROM public.client_profiles 
--    WHERE user_id = (SELECT id FROM public.users WHERE email = 'tu_email@test.com');
--
-- 3. Ver logs de debug:
--    SELECT * FROM public.debug_user_signup_log 
--    WHERE email = 'tu_email@test.com'
--    ORDER BY created_at DESC;
-- ============================================================================
