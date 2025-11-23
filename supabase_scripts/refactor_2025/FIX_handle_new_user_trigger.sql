-- =====================================================================
-- FIX: Trigger handle_new_user - CORRIGE ERROR 500 EN SIGNUP
-- =====================================================================
-- Este script corrige el trigger que falla cuando se crea un usuario nuevo.
-- El problema era que ensure_client_profile_and_account() intentaba insertar
-- una columna 'status' que NO EXISTE en client_profiles.
-- =====================================================================

-- ====================================
-- PASO 1: CORREGIR FUNCIÓN ensure_client_profile_and_account
-- ====================================
-- Esta función ahora usa SOLO las columnas que existen en el schema real
-- ====================================
CREATE OR REPLACE FUNCTION public.ensure_client_profile_and_account(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_user_exists boolean;
  v_current_role text;
  v_account_id uuid;
  v_user_email text;
  v_user_name text;
  v_user_phone text;
BEGIN
  -- 1) Validar que el usuario existe en auth.users
  SELECT email, 
         raw_user_meta_data->>'name',
         raw_user_meta_data->>'phone'
  INTO v_user_email, v_user_name, v_user_phone
  FROM auth.users 
  WHERE id = p_user_id;
  
  IF v_user_email IS NULL THEN
    RAISE EXCEPTION 'User % not found in auth.users', p_user_id;
  END IF;

  -- 2) Verificar si el usuario ya existe en public.users
  SELECT role INTO v_current_role
  FROM public.users 
  WHERE id = p_user_id;
  
  v_user_exists := (v_current_role IS NOT NULL);

  -- 3) SOLO crear perfil de cliente si no tiene un role especializado
  IF v_current_role IS NOT NULL AND v_current_role NOT IN ('', 'cliente', 'client') THEN
    -- Ya tiene un role especializado (restaurante/repartidor/admin), no hacer nada
    RETURN jsonb_build_object(
      'success', true, 
      'account_id', NULL, 
      'skipped', true, 
      'reason', 'specialized_role'
    );
  END IF;

  -- 4) Crear/actualizar usuario en public.users con role='cliente'
  IF NOT v_user_exists THEN
    INSERT INTO public.users (
      id, 
      email, 
      name, 
      phone, 
      role, 
      email_confirm, 
      created_at, 
      updated_at
    )
    VALUES (
      p_user_id, 
      v_user_email, 
      v_user_name, 
      v_user_phone, 
      'cliente', 
      false, 
      v_now, 
      v_now
    )
    ON CONFLICT (id) DO NOTHING;
  ELSE
    -- Solo normalizar a 'cliente' si actualmente es vacío/cliente
    IF COALESCE(v_current_role, '') IN ('', 'cliente', 'client') THEN
      UPDATE public.users 
      SET 
        role = 'cliente',
        email = COALESCE(email, v_user_email),
        name = COALESCE(name, v_user_name),
        phone = COALESCE(phone, v_user_phone),
        updated_at = v_now 
      WHERE id = p_user_id;
    END IF;
  END IF;

  -- 5) Asegurar perfil de cliente (SOLO columnas que existen)
  INSERT INTO public.client_profiles (
    user_id, 
    created_at, 
    updated_at
  )
  VALUES (
    p_user_id, 
    v_now, 
    v_now
  )
  ON CONFLICT (user_id) DO UPDATE
    SET updated_at = EXCLUDED.updated_at;

  -- 6) Asegurar cuenta financiera tipo 'client' con balance 0
  SELECT id INTO v_account_id
  FROM public.accounts
  WHERE user_id = p_user_id AND account_type = 'client'
  LIMIT 1;
  
  IF v_account_id IS NULL THEN
    INSERT INTO public.accounts (
      user_id, 
      account_type, 
      balance, 
      created_at, 
      updated_at
    )
    VALUES (
      p_user_id, 
      'client', 
      0.0, 
      v_now, 
      v_now
    )
    RETURNING id INTO v_account_id;
  END IF;

  -- 7) Asegurar preferencias de usuario (defaults)
  INSERT INTO public.user_preferences (
    user_id, 
    has_seen_onboarding, 
    created_at, 
    updated_at
  )
  VALUES (
    p_user_id, 
    false, 
    v_now, 
    v_now
  )
  ON CONFLICT (user_id) DO NOTHING;

  -- 8) Retornar éxito
  RETURN jsonb_build_object(
    'success', true, 
    'account_id', v_account_id,
    'user_role', 'cliente'
  );
END;
$$;

-- ====================================
-- PASO 2: RECREAR FUNCIÓN handle_new_user
-- ====================================
-- Esta función se ejecuta automáticamente cuando se crea un usuario en auth.users
-- ====================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Llamar a la función corregida
  SELECT public.ensure_client_profile_and_account(NEW.id) INTO v_result;
  
  -- Log para debug (opcional)
  INSERT INTO public.debug_user_signup_log (
    source, 
    event, 
    role, 
    user_id, 
    email, 
    details, 
    created_at
  )
  VALUES (
    'trigger', 
    'handle_new_user', 
    'cliente', 
    NEW.id, 
    NEW.email, 
    v_result, 
    now()
  );
  
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log del error para debugging
  INSERT INTO public.debug_user_signup_log (
    source, 
    event, 
    role, 
    user_id, 
    email, 
    details, 
    created_at
  )
  VALUES (
    'trigger', 
    'handle_new_user_ERROR', 
    NULL, 
    NEW.id, 
    NEW.email, 
    jsonb_build_object(
      'error', SQLERRM,
      'detail', SQLSTATE
    ), 
    now()
  );
  
  -- Re-lanzar el error para que falle el signup
  RAISE;
END;
$$;

-- ====================================
-- PASO 3: RECREAR TRIGGER
-- ====================================
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS trg_handle_new_user_on_auth_users ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ====================================
-- VERIFICACIÓN
-- ====================================
SELECT 
  '[OK] Trigger corregido exitosamente' as status,
  'Trigger: on_auth_user_created' as trigger_name,
  'Function: public.handle_new_user()' as function_name;

-- Ver triggers existentes en auth.users
SELECT 
  trigger_name,
  event_manipulation,
  event_object_table,
  action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'auth'
  AND event_object_table = 'users'
ORDER BY trigger_name;

-- ====================================
-- PRUEBA RÁPIDA
-- ====================================
SELECT 
  '[IMPORTANTE] INSTRUCCIONES DE PRUEBA' as titulo,
  '
  1. Ejecuta este script en el SQL Editor de Supabase
  2. Intenta crear un nuevo usuario desde la app
  3. Si funciona, verás el registro en:
     - auth.users
     - public.users (role=cliente)
     - public.client_profiles
     - public.accounts (account_type=client)
     - public.user_preferences
  
  4. Para debug, consulta:
     SELECT * FROM public.debug_user_signup_log 
     ORDER BY created_at DESC 
     LIMIT 10;
  
  5. Si el error persiste, checa los logs de Supabase en:
     Database > Logs > Postgres Logs
  ' as instrucciones;
