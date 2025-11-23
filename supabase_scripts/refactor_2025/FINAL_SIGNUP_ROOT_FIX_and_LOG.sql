-- =====================================================================================
-- ✅ FIX DEFINITIVO: Signup 500 (Database error saving new user)
-- Objetivo: Alinear ensure_client_profile_and_account() y handle_new_user() al schema real
--           e impedir que el trigger rompa el signup. Agrega logging claro.
-- Fuente de verdad de columnas: supabase_scripts/DATABASE_SCHEMA.sql
-- =====================================================================================

-- 0) Helper: asegurar que existe tabla de logs (no falla si ya existe)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema='public' AND table_name='debug_user_signup_log'
  ) THEN
    CREATE TABLE public.debug_user_signup_log (
      id bigserial PRIMARY KEY,
      source text,
      event text,
      role text,
      user_id uuid,
      email text,
      details jsonb,
      created_at timestamptz DEFAULT now()
    );
  END IF;
END $$;

-- 1) Asegurar que accounts.account_type acepta 'client'
DO $$
DECLARE v_name text; v_def text; BEGIN
  SELECT conname, pg_get_constraintdef(oid) INTO v_name, v_def
  FROM pg_constraint c
  JOIN pg_class t ON c.conrelid = t.oid
  JOIN pg_namespace n ON t.relnamespace = n.oid
  WHERE n.nspname='public' AND t.relname='accounts' AND c.contype='c'
  ORDER BY c.oid LIMIT 1;
  IF v_name IS NOT NULL AND v_def IS NOT NULL AND position('client' in v_def) = 0 THEN
    EXECUTE format('ALTER TABLE public.accounts DROP CONSTRAINT %I', v_name);
    ALTER TABLE public.accounts ADD CONSTRAINT accounts_account_type_check
      CHECK (account_type IN ('client','restaurant','delivery_agent','platform','platform_revenue','platform_payables'));
  END IF;
END $$;

-- 2) Función definitiva: incluye email en public.users, crea perfil con status, y cuenta client
DROP FUNCTION IF EXISTS public.ensure_client_profile_and_account(uuid);
CREATE OR REPLACE FUNCTION public.ensure_client_profile_and_account(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_email text;
  v_role text;
  v_account_id uuid;
BEGIN
  -- Leer email desde auth.users (requerido por public.users.email NOT NULL UNIQUE)
  SELECT email INTO v_email FROM auth.users WHERE id = p_user_id;
  IF v_email IS NULL THEN
    INSERT INTO public.debug_user_signup_log(source,event,user_id,details)
    VALUES ('ensure_client_profile_and_account','AUTH_USER_NOT_FOUND', p_user_id, jsonb_build_object('hint','no email in auth.users'));
    RETURN jsonb_build_object('success', false, 'error', 'auth_user_missing');
  END IF;

  -- Upsert en public.users alineado a DATABASE_SCHEMA.sql
  -- Roles válidos: 'cliente','restaurante','repartidor','admin'
  INSERT INTO public.users (id, email, role, created_at, updated_at)
  VALUES (p_user_id, v_email, 'cliente', v_now, v_now)
  ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        updated_at = v_now
  RETURNING role INTO v_role;

  -- Asegurar perfil de cliente con status='active'
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

  INSERT INTO public.debug_user_signup_log(source,event,role,user_id,email,details)
  VALUES ('ensure_client_profile_and_account','SUCCESS', v_role, p_user_id, v_email,
          jsonb_build_object('account_id', v_account_id));

  RETURN jsonb_build_object('success', true, 'role', v_role, 'account_id', v_account_id);
EXCEPTION WHEN OTHERS THEN
  INSERT INTO public.debug_user_signup_log(source,event,user_id,email,details)
  VALUES ('ensure_client_profile_and_account','ERROR', p_user_id, v_email, jsonb_build_object('message', SQLERRM, 'state', SQLSTATE));
  -- No relanzar para evitar romper flujos que la llaman desde triggers endurecidos
  RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'state', SQLSTATE);
END;
$$;

COMMENT ON FUNCTION public.ensure_client_profile_and_account(uuid) IS 
  'Upsert public.users with email (role=cliente), ensure client_profiles(status=active) and accounts(client). Logs to debug_user_signup_log.';

GRANT EXECUTE ON FUNCTION public.ensure_client_profile_and_account(uuid) TO anon, authenticated, service_role;

-- 3) Endurecer trigger: nunca romper signup; loguear errores
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_result jsonb; v_email text; BEGIN
  SELECT email INTO v_email FROM auth.users WHERE id = NEW.id;
  BEGIN
    v_result := public.ensure_client_profile_and_account(NEW.id);
    INSERT INTO public.debug_user_signup_log(source,event,user_id,email,details)
    VALUES ('handle_new_user','TRIGGER_FIRED', NEW.id, v_email, jsonb_build_object('result', v_result));
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.debug_user_signup_log(source,event,user_id,email,details)
    VALUES ('handle_new_user','ERROR', NEW.id, v_email, jsonb_build_object('message', SQLERRM, 'state', SQLSTATE));
    -- Nunca relanzar
  END;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_user IS 'Auth signup trigger: calls ensure_client_profile_and_account and never raises; logs to debug_user_signup_log';

-- Nota: No intentamos crear/actualizar el trigger en auth.users para evitar errores de permisos.
--       Si ya existe, seguirá apuntando a public.handle_new_user() (actualizada).

-- 4) Verificación rápida (opcional)
-- SELECT pg_get_functiondef('public.ensure_client_profile_and_account(uuid)'::regprocedure);
-- SELECT pg_get_functiondef('public.handle_new_user()'::regprocedure);

-- 5) Consulta de logs (ejecutar tras intentar un signup)
-- SELECT * FROM public.debug_user_signup_log ORDER BY created_at DESC LIMIT 50;

-- =====================================================================================
-- FIN FIX
-- =====================================================================================
