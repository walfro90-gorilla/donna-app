-- ============================================================================
-- Script: 13_update_client_registration_rpc_FIXED.sql
-- Descripcion: Actualiza la funcion de registro de cliente para usar 'status'
--              VERSION CORREGIDA - Sin modificar trigger de auth.users
-- Autor: Sistema
-- Fecha: 2025-01-XX
-- Prerequisito: Ejecutar 12_add_status_to_client_profiles.sql primero
-- ============================================================================

-- PASO 1: Recrear función ensure_client_profile_and_account
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ensure_client_profile_and_account(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current_role text;
  v_account_id uuid;
  v_now timestamptz := now();
BEGIN
  -- Obtener rol actual
  SELECT role INTO v_current_role FROM public.users WHERE id = p_user_id;

  -- Si es el primer acceso (role vacío o null), asignar 'client'
  IF v_current_role IS NULL OR v_current_role = '' THEN
    INSERT INTO public.users (id, role, created_at, updated_at)
    VALUES (p_user_id, 'client', v_now, v_now)
    ON CONFLICT (id) DO NOTHING;
  ELSE
    -- Solo normalizar a 'client' si actualmente es vacío/cliente
    IF COALESCE(v_current_role, '') IN ('', 'client', 'cliente') THEN
      UPDATE public.users SET role = 'client', updated_at = v_now WHERE id = p_user_id;
    END IF;
  END IF;

  -- Asegurar profile de cliente CON status='active'
  INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
  VALUES (p_user_id, 'active', v_now, v_now)
  ON CONFLICT (user_id) DO UPDATE
    SET updated_at = EXCLUDED.updated_at;

  -- Asegurar cuenta financiera tipo 'client'
  SELECT id INTO v_account_id
  FROM public.accounts
  WHERE user_id = p_user_id AND account_type = 'client'
  LIMIT 1;
  
  IF v_account_id IS NULL THEN
    INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
    VALUES (p_user_id, 'client', 0.0, v_now, v_now)
    RETURNING id INTO v_account_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 
    'account_id', v_account_id,
    'status', 'active'
  );
END;
$$;

COMMENT ON FUNCTION public.ensure_client_profile_and_account IS 
'Asegura que un usuario tenga perfil de cliente con status=active y cuenta financiera';


-- PASO 2: Verificar trigger existente (NO MODIFICAR)
-- ============================================================================
-- NOTA: NO recreamos el trigger porque requiere permisos de OWNER
-- El trigger ya existe y se llama 'on_auth_user_created' o 'handle_new_user'
-- Solo verificamos que existe

DO $$
DECLARE
  v_trigger_exists boolean;
  v_trigger_name text;
BEGIN
  -- Buscar trigger en auth.users
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'auth' 
    AND c.relname = 'users'
    AND t.tgname IN ('on_auth_user_created', 'handle_new_user')
  ) INTO v_trigger_exists;

  IF v_trigger_exists THEN
    SELECT t.tgname INTO v_trigger_name
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'auth' 
    AND c.relname = 'users'
    AND t.tgname IN ('on_auth_user_created', 'handle_new_user')
    LIMIT 1;
    
    RAISE NOTICE '[OK] Trigger existente encontrado: %', v_trigger_name;
    RAISE NOTICE '[INFO] El trigger YA LLAMA a ensure_client_profile_and_account()';
    RAISE NOTICE '[INFO] La actualizacion de la funcion es suficiente';
  ELSE
    RAISE WARNING '[WARNING] No se encontro trigger en auth.users';
    RAISE WARNING '[ACTION] Debes crear el trigger manualmente con usuario OWNER';
  END IF;
END $$;


-- PASO 3: Actualizar función handle_new_user (sin recrear trigger)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Insertar en public.users
  INSERT INTO public.users (id, email, name, phone, role, email_confirm, created_at, updated_at)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', ''),
    COALESCE(NEW.raw_user_meta_data->>'phone', ''),
    COALESCE(NEW.raw_user_meta_data->>'role', 'client'),
    NEW.email_confirmed_at IS NOT NULL,
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE
  SET 
    email = EXCLUDED.email,
    name = EXCLUDED.name,
    phone = EXCLUDED.phone,
    email_confirm = EXCLUDED.email_confirm,
    updated_at = now();

  -- Por defecto crear client_profile + account (con status='active')
  v_result := public.ensure_client_profile_and_account(NEW.id);

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_user IS 
'Funcion trigger que crea automáticamente public.users, client_profiles (con status=active) y accounts';


-- PASO 4: Verificar que todo esté correcto
-- ============================================================================
DO $$
DECLARE
  v_function1_exists boolean;
  v_function2_exists boolean;
  v_column_exists boolean;
BEGIN
  -- Verificar función ensure_client_profile_and_account
  SELECT EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'ensure_client_profile_and_account'
  ) INTO v_function1_exists;

  IF v_function1_exists THEN
    RAISE NOTICE '[OK] Funcion ensure_client_profile_and_account existe';
  ELSE
    RAISE EXCEPTION '[ERROR] Funcion ensure_client_profile_and_account NO existe';
  END IF;

  -- Verificar función handle_new_user
  SELECT EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'handle_new_user'
  ) INTO v_function2_exists;

  IF v_function2_exists THEN
    RAISE NOTICE '[OK] Funcion handle_new_user existe';
  ELSE
    RAISE EXCEPTION '[ERROR] Funcion handle_new_user NO existe';
  END IF;

  -- Verificar columna status
  SELECT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'client_profiles' 
    AND column_name = 'status'
  ) INTO v_column_exists;

  IF v_column_exists THEN
    RAISE NOTICE '[OK] Columna status existe en client_profiles';
  ELSE
    RAISE EXCEPTION '[ERROR] Columna status NO existe en client_profiles';
  END IF;

  RAISE NOTICE '[SUCCESS] Sistema de registro de cliente actualizado correctamente';
  RAISE NOTICE '[INFO] Si el trigger ya existe, la actualizacion esta completa';
  RAISE NOTICE '[INFO] Si el trigger NO existe, ejecuta: 14_create_trigger_manually.sql';
END $$;


-- ============================================================================
-- FIN DEL SCRIPT
-- ============================================================================
