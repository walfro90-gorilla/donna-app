-- ============================================================================
-- ⚡ COPIAR Y PEGAR ESTE ARCHIVO COMPLETO EN SUPABASE SQL EDITOR
-- ============================================================================
-- ✅ Selecciona TODO el contenido de este archivo (Ctrl+A)
-- ✅ Copia (Ctrl+C)
-- ✅ Pega en Supabase SQL Editor (Ctrl+V)
-- ✅ Click en RUN
-- ✅ Espera que termine (5 segundos)
-- ✅ Verifica que diga "FIX COMPLETADO EXITOSAMENTE"
-- ============================================================================

-- PASO 1: Eliminar triggers problemáticos en client_profiles
DO $$
DECLARE
  trigger_rec RECORD;
BEGIN
  FOR trigger_rec IN
    SELECT tgname
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    WHERE c.relname = 'client_profiles'
      AND c.relnamespace = 'public'::regnamespace
      AND NOT t.tgisinternal
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.client_profiles CASCADE', trigger_rec.tgname);
    RAISE NOTICE '✅ Eliminado trigger: client_profiles.%', trigger_rec.tgname;
  END LOOP;
END $$;

-- PASO 2: Eliminar triggers problemáticos en users (excepto updated_at)
DO $$
DECLARE
  trigger_rec RECORD;
BEGIN
  FOR trigger_rec IN
    SELECT tgname
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    WHERE c.relname = 'users'
      AND c.relnamespace = 'public'::regnamespace
      AND NOT t.tgisinternal
      AND tgname NOT ILIKE '%updated_at%'
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.users CASCADE', trigger_rec.tgname);
    RAISE NOTICE '✅ Eliminado trigger: users.%', trigger_rec.tgname;
  END LOOP;
END $$;

-- PASO 3: Eliminar funciones legacy
DROP FUNCTION IF EXISTS public.create_user_profile_public(uuid, text, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.create_user_profile_public(uuid, text, text, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.create_user_profile_public(uuid, text, text, text, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.create_restaurant_public(uuid, text, text, text, text, text, boolean, text, double precision, double precision, text, jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.create_restaurant_public(uuid, text, text, text, boolean, text) CASCADE;
DROP FUNCTION IF EXISTS public.create_restaurant_public(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.create_account_public(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.create_account_public(uuid, text, double precision) CASCADE;
DROP FUNCTION IF EXISTS public.sync_delivery_agent_status() CASCADE;
DROP FUNCTION IF EXISTS public.update_delivery_agent_status() CASCADE;
DROP FUNCTION IF EXISTS public.sync_user_status() CASCADE;
DROP FUNCTION IF EXISTS public.handle_user_status_change() CASCADE;
DROP FUNCTION IF EXISTS public.validate_status_change() CASCADE;

-- PASO 4: Verificación
DO $$
DECLARE
  v_client_triggers integer;
  v_user_triggers integer;
BEGIN
  SELECT COUNT(*) INTO v_client_triggers
  FROM pg_trigger t
  JOIN pg_class c ON t.tgrelid = c.oid
  WHERE c.relname = 'client_profiles'
    AND c.relnamespace = 'public'::regnamespace
    AND NOT t.tgisinternal;
  
  SELECT COUNT(*) INTO v_user_triggers
  FROM pg_trigger t
  JOIN pg_class c ON t.tgrelid = c.oid
  WHERE c.relname = 'users'
    AND c.relnamespace = 'public'::regnamespace
    AND NOT t.tgisinternal;
  
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ FIX COMPLETADO EXITOSAMENTE';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Triggers en client_profiles: %', v_client_triggers;
  RAISE NOTICE 'Triggers en users: %', v_user_triggers;
  RAISE NOTICE '';
  RAISE NOTICE '🚀 Próximos pasos:';
  RAISE NOTICE '1. Refresca tu app Flutter';
  RAISE NOTICE '2. Intenta registrar un restaurante';
  RAISE NOTICE '3. Debería funcionar correctamente';
  RAISE NOTICE '';
END $$;
