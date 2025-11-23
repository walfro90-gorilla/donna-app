-- ============================================================================
-- FASE 2 - SCRIPT 06: CONFIGURAR PERMISOS
-- ============================================================================
-- Descripción: Asegura que los permisos estén correctamente configurados
--              para que el signup funcione de manera segura.
-- ============================================================================

-- ============================================================================
-- REVOCAR PERMISOS DE FUNCIONES OBSOLETAS (por si aún existen)
-- ============================================================================

-- Funciones de signup que NO deben ser ejecutables públicamente
DO $$
DECLARE
  func_name TEXT;
BEGIN
  FOR func_name IN 
    SELECT proname::text 
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND proname IN (
        'register_client',
        'register_delivery_agent',
        'register_delivery_agent_atomic',
        'register_restaurant',
        'register_restaurant_v2',
        'create_user_profile_public',
        'create_delivery_agent',
        'create_restaurant_public',
        'ensure_user_profile_public',
        'ensure_user_profile_v2',
        'ensure_client_profile_and_account',
        'ensure_delivery_agent_role_and_profile',
        'ensure_my_delivery_profile'
      )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I FROM PUBLIC, anon, authenticated', func_name);
    RAISE NOTICE '✅ Permisos revocados: %', func_name;
  END LOOP;
END $$;

-- ============================================================================
-- ASEGURAR PERMISOS DE master_handle_signup
-- ============================================================================

DO $$
BEGIN
  -- Esta función solo debe ser ejecutada por el trigger (postgres role)
  REVOKE ALL ON FUNCTION public.master_handle_signup() FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.master_handle_signup() FROM anon;
  REVOKE ALL ON FUNCTION public.master_handle_signup() FROM authenticated;
  GRANT EXECUTE ON FUNCTION public.master_handle_signup() TO postgres;

  RAISE NOTICE '✅ Permisos configurados: master_handle_signup() → SOLO postgres';

  -- ============================================================================
  -- ASEGURAR PERMISOS DE TABLAS CRÍTICAS
  -- ============================================================================

  -- users: anon NO debe poder leer/escribir directamente
  REVOKE ALL ON TABLE public.users FROM anon;
  GRANT SELECT ON TABLE public.users TO authenticated; -- Solo usuarios autenticados pueden leer

  RAISE NOTICE '✅ Permisos configurados: public.users → authenticated (SELECT only)';

  -- client_profiles: anon NO debe poder escribir directamente
  REVOKE INSERT, UPDATE, DELETE ON TABLE public.client_profiles FROM anon;
  GRANT SELECT ON TABLE public.client_profiles TO authenticated;

  RAISE NOTICE '✅ Permisos configurados: public.client_profiles → authenticated (SELECT only)';

  -- delivery_agent_profiles: anon NO debe poder escribir directamente
  REVOKE INSERT, UPDATE, DELETE ON TABLE public.delivery_agent_profiles FROM anon;
  GRANT SELECT ON TABLE public.delivery_agent_profiles TO authenticated;

  RAISE NOTICE '✅ Permisos configurados: public.delivery_agent_profiles → authenticated (SELECT only)';

  -- restaurants: anon puede ver restaurantes, pero NO crear directamente
  REVOKE INSERT, UPDATE, DELETE ON TABLE public.restaurants FROM anon;
  GRANT SELECT ON TABLE public.restaurants TO anon, authenticated;

  RAISE NOTICE '✅ Permisos configurados: public.restaurants → anon/authenticated (SELECT only)';

  -- accounts: anon NO debe poder ver ni escribir
  REVOKE ALL ON TABLE public.accounts FROM anon;
  GRANT SELECT ON TABLE public.accounts TO authenticated; -- Solo el dueño puede ver su cuenta (RLS)

  RAISE NOTICE '✅ Permisos configurados: public.accounts → authenticated (SELECT only with RLS)';

  -- user_preferences: anon NO debe poder escribir directamente
  REVOKE INSERT, UPDATE, DELETE ON TABLE public.user_preferences FROM anon;
  GRANT SELECT ON TABLE public.user_preferences TO authenticated;

  RAISE NOTICE '✅ Permisos configurados: public.user_preferences → authenticated (SELECT only)';

  -- ============================================================================
  -- ASEGURAR PERMISOS DE debug_user_signup_log
  -- ============================================================================

  -- Solo postgres puede insertar en debug_user_signup_log
  REVOKE ALL ON TABLE public.debug_user_signup_log FROM PUBLIC, anon, authenticated;
  GRANT SELECT ON TABLE public.debug_user_signup_log TO authenticated; -- Para debugging
  GRANT INSERT ON TABLE public.debug_user_signup_log TO postgres; -- Solo el trigger

  RAISE NOTICE '✅ Permisos configurados: debug_user_signup_log → postgres (INSERT), authenticated (SELECT)';

  -- ============================================================================
  -- MANTENER PERMISOS DE RPCs ÚTILES
  -- ============================================================================

  -- Funciones que SÍ deben ser accesibles públicamente
  GRANT EXECUTE ON FUNCTION public.check_email_availability(text) TO anon, authenticated;
  GRANT EXECUTE ON FUNCTION public.check_phone_availability(text) TO anon, authenticated;
  GRANT EXECUTE ON FUNCTION public.check_restaurant_name_availability(text) TO anon, authenticated;

  RAISE NOTICE '✅ Permisos mantenidos: check_*_availability() → anon/authenticated';

  -- Funciones de admin
  -- (Nota: RLS y lógica interna deben verificar is_admin())
  GRANT EXECUTE ON FUNCTION public.admin_approve_user(uuid, text) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.admin_approve_delivery_agent(uuid) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.admin_approve_restaurant(uuid, boolean, text) TO authenticated;

  RAISE NOTICE '✅ Permisos mantenidos: admin_*() → authenticated (con verificación is_admin() interna)';

  -- ============================================================================
  -- VERIFICAR PERMISOS DE SECUENCIAS (para uuid_generate_v4)
  -- ============================================================================

  -- Asegurar que la extensión uuid-ossp está habilitada
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

  RAISE NOTICE '✅ Extensión verificada: uuid-ossp';
END $$;

-- ============================================================================
-- VERIFICACIÓN FINAL
-- ============================================================================

DO $$
DECLARE
  v_master_function_exists BOOLEAN;
  v_trigger_exists BOOLEAN;
BEGIN
  -- Verificar que master_handle_signup existe
  SELECT EXISTS(
    SELECT 1 FROM pg_proc 
    WHERE proname = 'master_handle_signup' 
      AND pronamespace = 'public'::regnamespace
  ) INTO v_master_function_exists;

  -- Verificar que el trigger existe
  SELECT EXISTS(
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'on_auth_user_created' 
      AND tgrelid = 'auth.users'::regclass
  ) INTO v_trigger_exists;

  IF v_master_function_exists AND v_trigger_exists THEN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ FASE 2 COMPLETADA';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Función maestra: master_handle_signup() ✅';
    RAISE NOTICE 'Trigger activo: on_auth_user_created ✅';
    RAISE NOTICE 'Permisos configurados: ✅';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Resumen de Fase 2:';
    RAISE NOTICE '   ✅ Función maestra creada';
    RAISE NOTICE '   ✅ Trigger reemplazado en auth.users';
    RAISE NOTICE '   ✅ Permisos configurados correctamente';
    RAISE NOTICE '';
    RAISE NOTICE '🚀 Puedes continuar con FASE 3:';
    RAISE NOTICE '   07_validation_test_signup.sql';
  ELSE
    RAISE EXCEPTION 'ERROR: La función o el trigger NO fueron creados correctamente';
  END IF;
END $$;

-- ============================================================================
-- NOTAS IMPORTANTES
-- ============================================================================

/*
NOTA 1: RLS (Row Level Security)
  - Los permisos aquí configurados son a nivel de tabla.
  - Las policies RLS deben estar configuradas en cada tabla para controlar
    el acceso a nivel de fila (ej: un usuario solo puede ver su propio perfil).
  - Verifica que las RLS policies estén activas en:
    * public.users
    * public.client_profiles
    * public.delivery_agent_profiles
    * public.restaurants
    * public.accounts
    * public.user_preferences

NOTA 2: Funciones de admin
  - Las funciones admin_*() tienen GRANT EXECUTE para authenticated,
    pero internamente deben verificar que auth.uid() sea admin usando is_admin().
  - Si no verifican el rol, CUALQUIER usuario autenticado podría ejecutarlas.

NOTA 3: Signup desde Flutter
  - Flutter debe llamar SOLO a supabase.auth.signUp()
  - NO debe llamar a ningún RPC de signup (register_*, create_*, ensure_*)
  - El trigger on_auth_user_created se encarga de TODO automáticamente
*/
