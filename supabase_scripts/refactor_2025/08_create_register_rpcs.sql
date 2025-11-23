-- =====================================================================
-- 08_create_register_rpcs.sql
-- Crea RPCs idempotentes para registro de perfiles a partir de auth.uid()
-- - register_client(p_name, p_phone, p_email, p_country, p_city, p_lat, p_lng, p_address)
-- - register_restaurant(p_company_name, p_contact_name, p_phone, p_email, p_lat, p_lng, p_address)
-- - register_delivery_agent(p_name, p_phone, p_email, p_document_id, p_vehicle_type, p_lat, p_lng, p_address)
-- Notas:
--  • Cada función es SECURITY DEFINER, valida que auth.uid() no sea NULL.
--  • Inserta/actualiza en public.users y en la tabla específica si existen.
--  • Usa SQL dinámico para actualizar columnas opcionales solo si existen.
--  • Idempotente: safe ante múltiples ejecuciones.
-- =====================================================================

-- 0) Limpieza de overloads ambiguos antes de recrear
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN (
    SELECT p.oid,
           n.nspname AS schema_name,
           p.proname AS fn_name,
           pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('register_client','register_restaurant','register_delivery_agent')
  ) LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s);', r.schema_name, r.fn_name, r.args);
  END LOOP;
END$$;

-- Helper: verifica existencia de tabla
CREATE OR REPLACE FUNCTION public._table_exists(p_schema text, p_table text)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = p_schema AND table_name = p_table
  );
$$;

-- Helper: verifica existencia de columna
CREATE OR REPLACE FUNCTION public._column_exists(p_schema text, p_table text, p_column text)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = p_schema AND table_name = p_table AND column_name = p_column
  );
$$;

-- =====================================================================
-- register_client
-- =====================================================================
CREATE OR REPLACE FUNCTION public.register_client(
  p_name          text DEFAULT NULL,
  p_phone         text DEFAULT NULL,
  p_email         text DEFAULT NULL,
  p_country       text DEFAULT NULL,
  p_city          text DEFAULT NULL,
  p_lat           double precision DEFAULT NULL,
  p_lng           double precision DEFAULT NULL,
  p_address       jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_created_users boolean := false;
  v_created_role  boolean := false;
  v_users_has_role boolean := false;
  v_json jsonb := '{}'::jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated (auth.uid() is null)';
  END IF;

  -- users: insert minimal
  IF (SELECT NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_uid)) THEN
    IF public._column_exists('public','users','id') THEN
      EXECUTE 'INSERT INTO public.users(id) VALUES ($1) ON CONFLICT DO NOTHING' USING v_uid;
      v_created_users := true;
    ELSE
      RAISE EXCEPTION 'Table public.users without id column. Please align schema.';
    END IF;
  END IF;

  -- users.role = 'client' si existe columna
  IF public._column_exists('public','users','role') THEN
    EXECUTE 'UPDATE public.users SET role = $1 WHERE id = $2 AND (role IS NULL OR role <> $1)'
    USING 'client', v_uid;
    v_users_has_role := true;
  END IF;

  -- users.name/email/phone opcionales
  IF p_name IS NOT NULL AND public._column_exists('public','users','name') THEN
    EXECUTE 'UPDATE public.users SET name = $1 WHERE id = $2' USING p_name, v_uid;
  END IF;
  IF p_phone IS NOT NULL AND public._column_exists('public','users','phone') THEN
    EXECUTE 'UPDATE public.users SET phone = $1 WHERE id = $2' USING p_phone, v_uid;
  END IF;
  IF p_email IS NOT NULL AND public._column_exists('public','users','email') THEN
    EXECUTE 'UPDATE public.users SET email = $1 WHERE id = $2' USING p_email, v_uid;
  END IF;

  -- clients: crear si existe tabla
  IF public._table_exists('public','clients') THEN
    EXECUTE 'INSERT INTO public.clients(user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING' USING v_uid;
    v_created_role := true;

    -- columnas opcionales conocidas
    IF p_name IS NOT NULL AND public._column_exists('public','clients','name') THEN
      EXECUTE 'UPDATE public.clients SET name = $1 WHERE user_id = $2' USING p_name, v_uid;
    END IF;
    IF p_phone IS NOT NULL AND public._column_exists('public','clients','phone') THEN
      EXECUTE 'UPDATE public.clients SET phone = $1 WHERE user_id = $2' USING p_phone, v_uid;
    END IF;
    IF p_country IS NOT NULL AND public._column_exists('public','clients','country') THEN
      EXECUTE 'UPDATE public.clients SET country = $1 WHERE user_id = $2' USING p_country, v_uid;
    END IF;
    IF p_city IS NOT NULL AND public._column_exists('public','clients','city') THEN
      EXECUTE 'UPDATE public.clients SET city = $1 WHERE user_id = $2' USING p_city, v_uid;
    END IF;
    IF p_lat IS NOT NULL AND public._column_exists('public','clients','lat') THEN
      EXECUTE 'UPDATE public.clients SET lat = $1 WHERE user_id = $2' USING p_lat, v_uid;
    END IF;
    IF p_lng IS NOT NULL AND public._column_exists('public','clients','lng') THEN
      EXECUTE 'UPDATE public.clients SET lng = $1 WHERE user_id = $2' USING p_lng, v_uid;
    END IF;
    IF p_address IS NOT NULL AND public._column_exists('public','clients','address') THEN
      EXECUTE 'UPDATE public.clients SET address = $1 WHERE user_id = $2' USING p_address, v_uid;
    END IF;
  END IF;

  v_json := jsonb_build_object(
    'user_id', v_uid::text,
    'created_user_row', v_created_users,
    'set_user_role', v_users_has_role,
    'created_client_row', v_created_role
  );
  RETURN v_json;
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_client(text, text, text, text, text, double precision, double precision, jsonb) TO authenticated, anon;

-- =====================================================================
-- register_restaurant
-- =====================================================================
CREATE OR REPLACE FUNCTION public.register_restaurant(
  p_company_name  text DEFAULT NULL,
  p_contact_name  text DEFAULT NULL,
  p_phone         text DEFAULT NULL,
  p_email         text DEFAULT NULL,
  p_lat           double precision DEFAULT NULL,
  p_lng           double precision DEFAULT NULL,
  p_address       jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_created_users boolean := false;
  v_created_role  boolean := false;
  v_users_has_role boolean := false;
  v_json jsonb := '{}'::jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated (auth.uid() is null)';
  END IF;

  IF (SELECT NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_uid)) THEN
    IF public._column_exists('public','users','id') THEN
      EXECUTE 'INSERT INTO public.users(id) VALUES ($1) ON CONFLICT DO NOTHING' USING v_uid;
      v_created_users := true;
    ELSE
      RAISE EXCEPTION 'Table public.users without id column. Please align schema.';
    END IF;
  END IF;

  IF public._column_exists('public','users','role') THEN
    EXECUTE 'UPDATE public.users SET role = $1 WHERE id = $2 AND (role IS NULL OR role <> $1)'
    USING 'restaurant', v_uid;
    v_users_has_role := true;
  END IF;

  IF p_contact_name IS NOT NULL AND public._column_exists('public','users','name') THEN
    EXECUTE 'UPDATE public.users SET name = $1 WHERE id = $2' USING p_contact_name, v_uid;
  END IF;
  IF p_phone IS NOT NULL AND public._column_exists('public','users','phone') THEN
    EXECUTE 'UPDATE public.users SET phone = $1 WHERE id = $2' USING p_phone, v_uid;
  END IF;
  IF p_email IS NOT NULL AND public._column_exists('public','users','email') THEN
    EXECUTE 'UPDATE public.users SET email = $1 WHERE id = $2' USING p_email, v_uid;
  END IF;

  IF public._table_exists('public','restaurants') THEN
    EXECUTE 'INSERT INTO public.restaurants(user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING' USING v_uid;
    v_created_role := true;

    IF p_company_name IS NOT NULL AND public._column_exists('public','restaurants','company_name') THEN
      EXECUTE 'UPDATE public.restaurants SET company_name = $1 WHERE user_id = $2' USING p_company_name, v_uid;
    END IF;
    IF p_contact_name IS NOT NULL AND public._column_exists('public','restaurants','contact_name') THEN
      EXECUTE 'UPDATE public.restaurants SET contact_name = $1 WHERE user_id = $2' USING p_contact_name, v_uid;
    END IF;
    IF p_phone IS NOT NULL AND public._column_exists('public','restaurants','phone') THEN
      EXECUTE 'UPDATE public.restaurants SET phone = $1 WHERE user_id = $2' USING p_phone, v_uid;
    END IF;
    IF p_lat IS NOT NULL AND public._column_exists('public','restaurants','lat') THEN
      EXECUTE 'UPDATE public.restaurants SET lat = $1 WHERE user_id = $2' USING p_lat, v_uid;
    END IF;
    IF p_lng IS NOT NULL AND public._column_exists('public','restaurants','lng') THEN
      EXECUTE 'UPDATE public.restaurants SET lng = $1 WHERE user_id = $2' USING p_lng, v_uid;
    END IF;
    IF p_address IS NOT NULL AND public._column_exists('public','restaurants','address') THEN
      EXECUTE 'UPDATE public.restaurants SET address = $1 WHERE user_id = $2' USING p_address, v_uid;
    END IF;
  END IF;

  v_json := jsonb_build_object(
    'user_id', v_uid::text,
    'created_user_row', v_created_users,
    'set_user_role', v_users_has_role,
    'created_restaurant_row', v_created_role
  );
  RETURN v_json;
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_restaurant(text, text, text, text, double precision, double precision, jsonb) TO authenticated, anon;

-- =====================================================================
-- register_delivery_agent
-- =====================================================================
CREATE OR REPLACE FUNCTION public.register_delivery_agent(
  p_name         text DEFAULT NULL,
  p_phone        text DEFAULT NULL,
  p_email        text DEFAULT NULL,
  p_document_id  text DEFAULT NULL,
  p_vehicle_type text DEFAULT NULL,
  p_lat          double precision DEFAULT NULL,
  p_lng          double precision DEFAULT NULL,
  p_address      jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_created_users boolean := false;
  v_created_role  boolean := false;
  v_users_has_role boolean := false;
  v_json jsonb := '{}'::jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated (auth.uid() is null)';
  END IF;

  IF (SELECT NOT EXISTS (SELECT 1 FROM public.users WHERE id = v_uid)) THEN
    IF public._column_exists('public','users','id') THEN
      EXECUTE 'INSERT INTO public.users(id) VALUES ($1) ON CONFLICT DO NOTHING' USING v_uid;
      v_created_users := true;
    ELSE
      RAISE EXCEPTION 'Table public.users without id column. Please align schema.';
    END IF;
  END IF;

  IF public._column_exists('public','users','role') THEN
    EXECUTE 'UPDATE public.users SET role = $1 WHERE id = $2 AND (role IS NULL OR role <> $1)'
    USING 'delivery_agent', v_uid;
    v_users_has_role := true;
  END IF;

  IF p_name IS NOT NULL AND public._column_exists('public','users','name') THEN
    EXECUTE 'UPDATE public.users SET name = $1 WHERE id = $2' USING p_name, v_uid;
  END IF;
  IF p_phone IS NOT NULL AND public._column_exists('public','users','phone') THEN
    EXECUTE 'UPDATE public.users SET phone = $1 WHERE id = $2' USING p_phone, v_uid;
  END IF;
  IF p_email IS NOT NULL AND public._column_exists('public','users','email') THEN
    EXECUTE 'UPDATE public.users SET email = $1 WHERE id = $2' USING p_email, v_uid;
  END IF;

  IF public._table_exists('public','delivery_agents') THEN
    EXECUTE 'INSERT INTO public.delivery_agents(user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING' USING v_uid;
    v_created_role := true;

    IF p_name IS NOT NULL AND public._column_exists('public','delivery_agents','name') THEN
      EXECUTE 'UPDATE public.delivery_agents SET name = $1 WHERE user_id = $2' USING p_name, v_uid;
    END IF;
    IF p_phone IS NOT NULL AND public._column_exists('public','delivery_agents','phone') THEN
      EXECUTE 'UPDATE public.delivery_agents SET phone = $1 WHERE user_id = $2' USING p_phone, v_uid;
    END IF;
    IF p_document_id IS NOT NULL AND public._column_exists('public','delivery_agents','document_id') THEN
      EXECUTE 'UPDATE public.delivery_agents SET document_id = $1 WHERE user_id = $2' USING p_document_id, v_uid;
    END IF;
    IF p_vehicle_type IS NOT NULL AND public._column_exists('public','delivery_agents','vehicle_type') THEN
      EXECUTE 'UPDATE public.delivery_agents SET vehicle_type = $1 WHERE user_id = $2' USING p_vehicle_type, v_uid;
    END IF;
    IF p_lat IS NOT NULL AND public._column_exists('public','delivery_agents','lat') THEN
      EXECUTE 'UPDATE public.delivery_agents SET lat = $1 WHERE user_id = $2' USING p_lat, v_uid;
    END IF;
    IF p_lng IS NOT NULL AND public._column_exists('public','delivery_agents','lng') THEN
      EXECUTE 'UPDATE public.delivery_agents SET lng = $1 WHERE user_id = $2' USING p_lng, v_uid;
    END IF;
    IF p_address IS NOT NULL AND public._column_exists('public','delivery_agents','address') THEN
      EXECUTE 'UPDATE public.delivery_agents SET address = $1 WHERE user_id = $2' USING p_address, v_uid;
    END IF;
  END IF;

  v_json := jsonb_build_object(
    'user_id', v_uid::text,
    'created_user_row', v_created_users,
    'set_user_role', v_users_has_role,
    'created_delivery_agent_row', v_created_role
  );
  RETURN v_json;
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_delivery_agent(text, text, text, text, text, double precision, double precision, jsonb) TO authenticated, anon;

-- Limpieza helpers si prefieres no dejarlos, comenta si deseas mantenerlos
-- (Se dejan para futuras migraciones idempotentes)
