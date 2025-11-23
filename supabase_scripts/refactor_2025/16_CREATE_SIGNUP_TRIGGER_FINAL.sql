-- =====================================================
-- ✅ SOLUCIÓN DEFINITIVA: Trigger de signup
-- =====================================================
-- Este script crea el trigger que faltaba para el signup
-- Basado en DATABASE_SCHEMA.sql
-- =====================================================

-- 🔧 1. CREAR FUNCIÓN handle_new_user()
-- =====================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  v_email TEXT;
  v_role TEXT := 'cliente'; -- Por defecto todos son clientes
BEGIN
  -- Obtener email del nuevo usuario en auth.users
  v_email := NEW.email;
  
  -- Log de inicio (para debugging)
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_new_user', 'START', v_role, NEW.id, v_email, jsonb_build_object('raw_user_meta_data', NEW.raw_user_meta_data));

  -- 📝 PASO 1: Insertar en public.users
  INSERT INTO public.users (id, email, role, name, created_at, updated_at, email_confirm)
  VALUES (
    NEW.id,
    v_email,
    v_role,
    COALESCE(NEW.raw_user_meta_data->>'name', v_email), -- Usar nombre del meta_data o email
    now(),
    now(),
    false
  )
  ON CONFLICT (id) DO UPDATE
  SET 
    email = EXCLUDED.email,
    updated_at = now();

  -- Log de public.users creado
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
  VALUES ('handle_new_user', 'USER_CREATED', v_role, NEW.id, v_email);

  -- 📝 PASO 2: Crear client_profile (status='active' es el default)
  INSERT INTO public.client_profiles (user_id, created_at, updated_at)
  VALUES (NEW.id, now(), now())
  ON CONFLICT (user_id) DO UPDATE
  SET updated_at = now();

  -- Log de client_profile creado
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
  VALUES ('handle_new_user', 'CLIENT_PROFILE_CREATED', v_role, NEW.id, v_email);

  -- 📝 PASO 3: Crear cuenta (account) para el cliente
  INSERT INTO public.accounts (id, user_id, account_type, balance, created_at, updated_at)
  VALUES (uuid_generate_v4(), NEW.id, 'client', 0.00, now(), now())
  ON CONFLICT DO NOTHING;

  -- Log de account creado
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
  VALUES ('handle_new_user', 'ACCOUNT_CREATED', v_role, NEW.id, v_email);

  -- 📝 PASO 4: Crear user_preferences
  INSERT INTO public.user_preferences (user_id, created_at, updated_at)
  VALUES (NEW.id, now(), now())
  ON CONFLICT (user_id) DO NOTHING;

  -- Log de SUCCESS
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
  VALUES ('handle_new_user', 'SUCCESS', v_role, NEW.id, v_email);

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Log de ERROR con detalles
    INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
    VALUES ('handle_new_user', 'ERROR', v_role, NEW.id, v_email, 
            jsonb_build_object('error', SQLERRM, 'state', SQLSTATE));
    
    -- Re-lanzar el error para que Supabase Auth devuelva 500
    RAISE;
END;
$$;

-- =====================================================
-- 🔧 2. CREAR TRIGGER EN auth.users
-- =====================================================
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- =====================================================
-- ✅ VERIFICACIÓN
-- =====================================================
SELECT 
  'TRIGGER_CREATED' as status,
  tgname as trigger_name,
  proname as function_name
FROM pg_trigger
JOIN pg_class ON pg_trigger.tgrelid = pg_class.oid
JOIN pg_namespace ON pg_class.relnamespace = pg_namespace.oid
JOIN pg_proc ON pg_trigger.tgfoid = pg_proc.oid
WHERE pg_namespace.nspname = 'auth'
  AND pg_class.relname = 'users'
  AND tgname = 'on_auth_user_created';

-- =====================================================
-- 📝 INSTRUCCIONES POST-INSTALACIÓN
-- =====================================================
-- 1. Ejecuta este script en el SQL Editor de Supabase
-- 2. Verifica que devuelva 1 fila con status='TRIGGER_CREATED'
-- 3. Intenta registrarte en la app con un email nuevo
-- 4. Si falla, ejecuta este query para ver los logs:
--    SELECT * FROM public.debug_user_signup_log ORDER BY created_at DESC LIMIT 10;
-- 5. Si todo funciona, limpia los logs de prueba:
--    DELETE FROM public.debug_user_signup_log WHERE email LIKE '%@test.com';
-- =====================================================
