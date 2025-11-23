-- =============================================================
-- Autocreación de perfiles de cliente y cuentas financieras
-- Plan Quirúrgico: alineado con Balance 0 y flujo actual
-- Seguro, idempotente y con RLS adecuado.
-- =============================================================

-- 1) Tabla client_profiles (mínima, extensible)
CREATE TABLE IF NOT EXISTS public.client_profiles (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  status text DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- RLS para client_profiles
ALTER TABLE public.client_profiles ENABLE ROW LEVEL SECURITY;

-- Permitir al dueño leer/actualizar su propio perfil
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'client_profiles' AND policyname = 'client_profiles_owner_select'
  ) THEN
    CREATE POLICY client_profiles_owner_select ON public.client_profiles
      FOR SELECT USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'client_profiles' AND policyname = 'client_profiles_owner_update'
  ) THEN
    CREATE POLICY client_profiles_owner_update ON public.client_profiles
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'client_profiles' AND policyname = 'client_profiles_owner_insert'
  ) THEN
    CREATE POLICY client_profiles_owner_insert ON public.client_profiles
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- 2) Asegurar que accounts acepta account_type 'client'
-- Si existe un CHECK sobre account_type, lo reemplazamos incluyendo 'client'.
DO $$
DECLARE
  v_constraint_name text;
  v_has_check boolean := false;
BEGIN
  SELECT conname INTO v_constraint_name
  FROM pg_constraint c
  JOIN pg_class t ON c.conrelid = t.oid
  JOIN pg_namespace n ON t.relnamespace = n.oid
  WHERE n.nspname = 'public' AND t.relname = 'accounts' AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) ILIKE '%account_type%';

  v_has_check := v_constraint_name IS NOT NULL;

  IF v_has_check THEN
    EXECUTE format('ALTER TABLE public.accounts DROP CONSTRAINT %I', v_constraint_name);
    -- Re-crear un CHECK amplio y permisivo que incluya client
    ALTER TABLE public.accounts
      ADD CONSTRAINT accounts_account_type_check
      CHECK (account_type IN (
        'restaurant','restaurante','delivery_agent','repartidor','platform','platform_revenue','platform_payables','client'
      ));
  END IF;
END $$;

-- 3) Helper: asegurar perfil de cliente y cuenta financiera 0
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
BEGIN
  -- Validar que el usuario existe en auth
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User % not found in auth.users', p_user_id;
  END IF;

  -- Verificar/crear public.users mínimo si no existe (rol cliente por defecto)
  SELECT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id), role
    INTO v_user_exists, v_current_role
  FROM public.users WHERE id = p_user_id;

  IF NOT v_user_exists THEN
    INSERT INTO public.users (id, role, created_at, updated_at)
    VALUES (p_user_id, 'client', v_now, v_now)
    ON CONFLICT (id) DO NOTHING;
  ELSE
    -- Normalizar rol solo si aún es cliente o nulo. No sobreescribir roles de restaurante/repartidor/admin
    IF COALESCE(v_current_role, '') IN ('', 'client', 'cliente') THEN
      UPDATE public.users SET role = 'client', updated_at = v_now WHERE id = p_user_id;
    END IF;
  END IF;

  -- Asegurar profile de cliente
  INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
  VALUES (p_user_id, 'active', v_now, v_now)
  ON CONFLICT (user_id) DO UPDATE
    SET updated_at = EXCLUDED.updated_at;

  -- Asegurar cuenta financiera tipo 'client' con balance 0 (específica por tipo)
  SELECT id INTO v_account_id
  FROM public.accounts
  WHERE user_id = p_user_id AND account_type = 'client'
  LIMIT 1;
  IF v_account_id IS NULL THEN
    INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
    VALUES (p_user_id, 'client', 0.0, v_now, v_now)
    RETURNING id INTO v_account_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'account_id', v_account_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_client_profile_and_account(uuid) TO anon, authenticated, service_role;

-- 4) Trigger en public.users: al insertar un usuario con rol cliente
-- Función wrapper para el trigger anterior (debe existir antes de crear el trigger)
CREATE OR REPLACE FUNCTION public._trg_call_ensure_client_profile_and_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.ensure_client_profile_and_account(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_client_profile_on_user_insert ON public.users;
CREATE TRIGGER trg_client_profile_on_user_insert
AFTER INSERT ON public.users
FOR EACH ROW
WHEN (NEW.role IN ('client','cliente'))
EXECUTE FUNCTION public._trg_call_ensure_client_profile_and_account();

-- 5) Trigger en public.accounts: si se crea cuenta tipo client, asegurar profile/rol
CREATE OR REPLACE FUNCTION public._trg_handle_client_account_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.ensure_client_profile_and_account(NEW.user_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_handle_client_account_insert ON public.accounts;
CREATE TRIGGER trg_handle_client_account_insert
AFTER INSERT ON public.accounts
FOR EACH ROW
WHEN (NEW.account_type = 'client')
EXECUTE FUNCTION public._trg_handle_client_account_insert();

-- 6) (Opcional y recomendado por el plan) Trigger en auth.users AFTER INSERT
--    En algunos proyectos no se permite crear triggers en esquema auth.
--    Si se permite, este bloque conecta el alta en Auth con la creación automática.
--    Definimos la función en public fuera del DO para evitar DDL dentro del bloque PL/pgSQL
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
BEGIN
  -- NEW.id, NEW.email disponibles desde auth.users
  PERFORM public.ensure_client_profile_and_account(NEW.id);
  RETURN NEW;
END;
$func$;

DO $$
BEGIN
  -- Intentar crear función/trigger solo si el esquema auth es editable (no falla la migración si no lo es)
  BEGIN
    -- Crear trigger si no existe previamente
    IF NOT EXISTS (
      SELECT 1 FROM pg_trigger WHERE tgname = 'trg_handle_new_user_on_auth_users'
    ) THEN
      EXECUTE 'CREATE TRIGGER trg_handle_new_user_on_auth_users
               AFTER INSERT ON auth.users
               FOR EACH ROW
               EXECUTE FUNCTION public.handle_new_user()';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- No bloquear la migración si no se puede crear el trigger en auth
    RAISE NOTICE 'No se pudo crear trigger en auth.users (no crítico): %', SQLERRM;
  END;
END $$;

-- 7) RPC para registrar deuda de cliente (doble asiento: cliente negativo, plataforma positivo)
CREATE OR REPLACE FUNCTION public.record_client_debt(
  p_user_id uuid,
  p_amount numeric,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_client_account uuid;
  v_platform_payables uuid;
  v_now timestamptz := now();
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be > 0';
  END IF;

  -- Asegurar que el cliente tiene perfil/cuenta
  PERFORM public.ensure_client_profile_and_account(p_user_id);

  SELECT id INTO v_client_account
  FROM public.accounts
  WHERE user_id = p_user_id
  ORDER BY (account_type = 'client') DESC
  LIMIT 1;

  -- Resolver cuenta flotante de plataforma
  SELECT id INTO v_platform_payables
  FROM public.accounts
  WHERE account_type = 'platform_payables'
  LIMIT 1;

  IF v_platform_payables IS NULL THEN
    -- Fallback por user_id seeded (según scripts 50/76/77/79/83/84)
    SELECT id INTO v_platform_payables FROM public.accounts
    WHERE user_id = '00000000-0000-0000-0000-000000000002'::uuid
    LIMIT 1;
  END IF;

  IF v_client_account IS NULL OR v_platform_payables IS NULL THEN
    RAISE EXCEPTION 'No se pudieron resolver cuentas (client/platform_payables)';
  END IF;

  -- Asiento doble (mantiene Balance 0)
  INSERT INTO public.account_transactions(account_id, type, amount, description, created_at)
  VALUES (v_client_account, 'CLIENT_DEBT', -p_amount, COALESCE(p_reason,'Deuda de cliente'), v_now);

  INSERT INTO public.account_transactions(account_id, type, amount, description, created_at)
  VALUES (v_platform_payables, 'CLIENT_DEBT', p_amount, COALESCE(p_reason,'Deuda de cliente (plataforma)'), v_now);

  -- Recalcular balances
  UPDATE public.accounts a SET balance = COALESCE( (
    SELECT SUM(amount) FROM public.account_transactions t WHERE t.account_id = a.id
  ), 0)
  WHERE a.id IN (v_client_account, v_platform_payables);

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_client_debt(uuid, numeric, text) TO authenticated, service_role;

-- 8) Backfill: crear perfiles/cuentas para clientes ya existentes
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT u.id FROM public.users u
    WHERE u.role IN ('client','cliente')
  LOOP
    PERFORM public.ensure_client_profile_and_account(r.id);
  END LOOP;
END $$;

-- 9) Verificaciones rápidas (opcionales)
-- SELECT * FROM public.client_profiles LIMIT 5;
-- SELECT account_type, count(*) FROM public.accounts GROUP BY 1;
-- SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgname IN ('trg_client_profile_on_user_insert','trg_handle_client_account_insert','trg_handle_new_user_on_auth_users');
