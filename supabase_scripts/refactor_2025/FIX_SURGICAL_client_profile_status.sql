-- ============================================================
-- FIX QUIRÚRGICO: Remover columna 'status' de client_profiles
-- ============================================================
-- PROBLEMA: La función ensure_client_profile_and_account() intenta 
-- insertar una columna 'status' que NO EXISTE en client_profiles
--
-- SOLUCIÓN: Recrear la función SIN la columna 'status'
-- ============================================================

-- ====================================
-- PASO 1: RECREAR ensure_client_profile_and_account
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
  v_auth_email text;
  v_auth_name text;
  v_auth_phone text;
BEGIN
  -- Log inicio
  INSERT INTO debug_user_signup_log (source, event, role, user_id, details)
  VALUES ('ensure_client_profile', 'start', 'cliente', p_user_id, jsonb_build_object('timestamp', v_now));

  -- Obtener datos de auth.users
  SELECT email, raw_user_meta_data->>'name', raw_user_meta_data->>'phone'
  INTO v_auth_email, v_auth_name, v_auth_phone
  FROM auth.users
  WHERE id = p_user_id;

  -- Validar que el usuario existe en auth
  IF v_auth_email IS NULL THEN
    RAISE EXCEPTION 'User % not found in auth.users', p_user_id;
  END IF;

  -- Verificar role actual
  SELECT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id), role
    INTO v_user_exists, v_current_role
  FROM public.users WHERE id = p_user_id;

  -- SOLO crear perfil de cliente si no tiene un role especializado
  IF v_current_role IS NOT NULL AND v_current_role NOT IN ('', 'client', 'cliente') THEN
    INSERT INTO debug_user_signup_log (source, event, role, user_id, details)
    VALUES ('ensure_client_profile', 'skip_specialized_role', v_current_role, p_user_id, 
            jsonb_build_object('reason', 'User already has specialized role'));
    
    RETURN jsonb_build_object('success', true, 'account_id', NULL, 'skipped', true, 'reason', 'specialized_role');
  END IF;

  -- Crear/actualizar usuario con role='cliente'
  IF NOT v_user_exists THEN
    INSERT INTO public.users (id, email, name, phone, role, created_at, updated_at, email_confirm)
    VALUES (p_user_id, v_auth_email, v_auth_name, v_auth_phone, 'cliente', v_now, v_now, false)
    ON CONFLICT (id) DO UPDATE
      SET email = EXCLUDED.email,
          name = COALESCE(EXCLUDED.name, users.name),
          phone = COALESCE(EXCLUDED.phone, users.phone),
          role = CASE 
            WHEN users.role IN ('', 'client') THEN 'cliente'
            ELSE users.role 
          END,
          updated_at = v_now;
    
    INSERT INTO debug_user_signup_log (source, event, role, user_id, email, details)
    VALUES ('ensure_client_profile', 'user_created', 'cliente', p_user_id, v_auth_email,
            jsonb_build_object('name', v_auth_name, 'phone', v_auth_phone));
  ELSE
    -- Solo normalizar a 'cliente' si actualmente es vacío/client
    IF COALESCE(v_current_role, '') IN ('', 'client', 'cliente') THEN
      UPDATE public.users 
      SET role = 'cliente', 
          updated_at = v_now,
          email = COALESCE(email, v_auth_email),
          name = COALESCE(name, v_auth_name),
          phone = COALESCE(phone, v_auth_phone)
      WHERE id = p_user_id;
      
      INSERT INTO debug_user_signup_log (source, event, role, user_id, details)
      VALUES ('ensure_client_profile', 'user_updated', 'cliente', p_user_id,
              jsonb_build_object('previous_role', v_current_role));
    END IF;
  END IF;

  -- ❌ REMOVIDO: columna 'status' que NO EXISTE
  -- ✅ CORRECTO: Solo columnas que existen en client_profiles
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

  INSERT INTO debug_user_signup_log (source, event, role, user_id, details)
  VALUES ('ensure_client_profile', 'profile_created', 'cliente', p_user_id,
          jsonb_build_object('timestamp', v_now));

  -- Asegurar cuenta financiera tipo 'client'
  SELECT id INTO v_account_id
  FROM public.accounts
  WHERE user_id = p_user_id AND account_type = 'client'
  LIMIT 1;
  
  IF v_account_id IS NULL THEN
    INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
    VALUES (p_user_id, 'client', 0.0, v_now, v_now)
    RETURNING id INTO v_account_id;
    
    INSERT INTO debug_user_signup_log (source, event, role, user_id, details)
    VALUES ('ensure_client_profile', 'account_created', 'cliente', p_user_id,
            jsonb_build_object('account_id', v_account_id, 'balance', 0.0));
  END IF;

  -- Asegurar user_preferences
  INSERT INTO public.user_preferences (user_id, created_at, updated_at)
  VALUES (p_user_id, v_now, v_now)
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO debug_user_signup_log (source, event, role, user_id, details)
  VALUES ('ensure_client_profile', 'success', 'cliente', p_user_id,
          jsonb_build_object('account_id', v_account_id));

  RETURN jsonb_build_object('success', true, 'account_id', v_account_id);
  
EXCEPTION
  WHEN OTHERS THEN
    INSERT INTO debug_user_signup_log (source, event, role, user_id, details)
    VALUES ('ensure_client_profile', 'error', 'cliente', p_user_id,
            jsonb_build_object('error', SQLERRM, 'sqlstate', SQLSTATE));
    
    RAISE;
END;
$$;

-- ====================================
-- PASO 2: VERIFICACIÓN
-- ====================================
SELECT 
  '[OK] Función corregida exitosamente' as status,
  'ensure_client_profile_and_account()' as function_name,
  'Columna status REMOVIDA' as fix_applied;

-- Ver la definición de la función
SELECT 
  routine_name,
  routine_type,
  data_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'ensure_client_profile_and_account';

-- ====================================
-- INSTRUCCIONES DE PRUEBA
-- ====================================
/*
1. Ejecuta este script en Supabase SQL Editor
2. Intenta registrar un nuevo usuario desde la app
3. Verifica los logs:
   SELECT * FROM debug_user_signup_log ORDER BY created_at DESC LIMIT 20;
4. Si falla, revisa los logs de Postgres en Dashboard > Logs
*/
