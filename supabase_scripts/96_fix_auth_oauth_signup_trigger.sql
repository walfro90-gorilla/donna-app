-- =============================================================
-- 96_fix_auth_oauth_signup_trigger.sql
-- Objetivo: Evitar "Database error saving new user" en OAuth
-- Causa probable: trigger AFTER INSERT en auth.users llamaba a una
--   función que insertaba en public.users sin cubrir columnas NOT NULL
--   (p.ej., email), provocando fallo en la transacción de alta.
-- Solución: Reescribir public.handle_new_user() para que:
--   1) Asegure el perfil en public.users con columnas mínimas disponibles
--      (dinámico, sin fallar si faltan columnas opcionales)
--   2) Llame a ensure_client_profile_and_account(p_user_id) para crear
--      client_profiles y la cuenta 'client' con balance 0.
--   3) Sea idempotente y tolerante a entornos sin ensure_user_profile_public.
-- =============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
  v_user_id uuid := NEW.id;
  v_email   text := NEW.email;
  v_name    text := COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', '');
  v_cols    text[];
  v_sql     text;
BEGIN
  -- 0) Intentar usar la RPC idempotente si existe (no es obligatoria)
  BEGIN
    PERFORM public.ensure_user_profile_public(v_user_id, v_email, v_name, 'client');
  EXCEPTION WHEN undefined_function THEN
    -- Continuar con inserción dinámica
  WHEN others THEN
    -- No bloquear por errores no críticos aquí; seguiremos con inserción dinámica
    NULL;
  END;

  -- 1) Inserción/Upsert dinámico en public.users para evitar errores por columnas faltantes
  --    Descubrir qué columnas están disponibles y construir un INSERT seguro
  SELECT ARRAY(
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users'
      AND column_name IN ('email','name','role','email_confirm','created_at','updated_at')
    ORDER BY 1
  ) INTO v_cols;

  -- Base con siempre la clave primaria id
  v_sql := 'INSERT INTO public.users (id';
  IF array_length(v_cols,1) IS NOT NULL THEN
    v_sql := v_sql || ', ' || array_to_string(v_cols, ', ');
  END IF;
  v_sql := v_sql || ') VALUES (' || quote_literal(v_user_id::text) || '';

  IF array_length(v_cols,1) IS NOT NULL THEN
    -- Mapear valores por columna conocida
    v_sql := v_sql || ', ' || (
      SELECT string_agg(
        CASE c
          WHEN 'email' THEN quote_nullable(v_email)
          WHEN 'name' THEN quote_nullable(v_name)
          WHEN 'role' THEN quote_literal('client')
          WHEN 'email_confirm' THEN 'true'
          WHEN 'created_at' THEN 'now()'
          WHEN 'updated_at' THEN 'now()'
        END, ', '
      )
      FROM unnest(v_cols) AS c
    );
  END IF;
  v_sql := v_sql || ') ON CONFLICT (id) DO UPDATE SET updated_at = now()';

  -- Si existen columnas email/name/role/email_confirm, actualizarlas también en conflicto
  IF array_position(v_cols, 'email') IS NOT NULL THEN
    v_sql := v_sql || ', email = EXCLUDED.email';
  END IF;
  IF array_position(v_cols, 'name') IS NOT NULL THEN
    v_sql := v_sql || ', name = EXCLUDED.name';
  END IF;
  IF array_position(v_cols, 'role') IS NOT NULL THEN
    v_sql := v_sql || ', role = EXCLUDED.role';
  END IF;
  IF array_position(v_cols, 'email_confirm') IS NOT NULL THEN
    v_sql := v_sql || ', email_confirm = EXCLUDED.email_confirm';
  END IF;

  -- Ejecutar upsert dinámico
  BEGIN
    EXECUTE v_sql;
  EXCEPTION WHEN others THEN
    -- No interrumpir el alta si falla por alguna razón no prevista; loguear como NOTICE
    RAISE NOTICE 'handle_new_user upsert public.users fallo: %', SQLERRM;
  END;

  -- 2) Asegurar perfil/cuenta financiera de cliente (idempotente)
  BEGIN
    PERFORM public.ensure_client_profile_and_account(v_user_id);
  EXCEPTION WHEN others THEN
    -- Registrar aviso pero no cancelar alta
    RAISE NOTICE 'ensure_client_profile_and_account fallo: %', SQLERRM;
  END;

  RETURN NEW;
END;
$func$;

-- Nota: No recreamos el trigger; reutilizamos el existente trg_handle_new_user_on_auth_users
-- que ya apunta a public.handle_new_user(). Esta actualización es idempotente.
