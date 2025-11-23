-- ============================================================================
-- 19_fix_auth_users_id_default.sql
-- Propósito: Corregir el error 500 en signup restaurando el default del PK
--            en auth.users.id a gen_random_uuid().
-- Contexto:  Tu diagnóstico muestra que auth.users.id es NOT NULL y SIN default.
--            GoTrue inserta sin proporcionar id y espera el default. Sin default,
--            el INSERT falla y devuelve 500 "Database error saving new user".
-- Seguro:    Idempotente. No altera datos existentes.
-- ============================================================================

-- 0) Asegurar extensión pgcrypto (provee gen_random_uuid) en schema extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 1) Asegurar que la columna id es uuid (no cambia si ya lo es)
DO $$
DECLARE
  v_is_uuid boolean;
BEGIN
  SELECT (data_type = 'uuid')
    INTO v_is_uuid
  FROM information_schema.columns
  WHERE table_schema = 'auth' AND table_name = 'users' AND column_name = 'id';

  IF NOT COALESCE(v_is_uuid, false) THEN
    -- Si no fuera uuid, convertir (esperado que ya sea uuid). No ejecuta si ya es uuid.
    EXECUTE 'ALTER TABLE auth.users ALTER COLUMN id TYPE uuid USING id::uuid';
  END IF;
END $$;

-- 2) Restaurar default a gen_random_uuid() sólo si falta o es distinto
DO $$
DECLARE
  v_current_default text;
BEGIN
  SELECT pg_get_expr(d.adbin, d.adrelid)
    INTO v_current_default
  FROM pg_attrdef d
  JOIN pg_class c ON c.oid = d.adrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = d.adnum
  WHERE n.nspname = 'auth' AND c.relname = 'users' AND a.attname = 'id';

  IF v_current_default IS NULL OR v_current_default NOT ILIKE '%gen_random_uuid()%'
  THEN
    -- Usamos schema-qualifier para evitar issues de search_path
    EXECUTE 'ALTER TABLE auth.users ALTER COLUMN id SET DEFAULT extensions.gen_random_uuid()';
  END IF;
END $$;

-- 3) Asegurar clave primaria en (id)
DO $$
DECLARE
  v_has_pk boolean;
BEGIN
  SELECT EXISTS (
           SELECT 1
           FROM pg_constraint con
           JOIN pg_class rel ON rel.oid = con.conrelid
           JOIN pg_namespace n ON n.oid = rel.relnamespace
           WHERE n.nspname = 'auth' AND rel.relname = 'users' AND con.contype = 'p'
         ) INTO v_has_pk;

  IF NOT v_has_pk THEN
    EXECUTE 'ALTER TABLE auth.users ADD PRIMARY KEY (id)';
  END IF;
END $$;

-- 4) Mostrar estado final (para verificación rápida en el editor)
SELECT
  'AUTH_USERS_ID_DEFAULT' AS step,
  column_default
FROM information_schema.columns
WHERE table_schema = 'auth' AND table_name = 'users' AND column_name = 'id';

SELECT
  'AUTH_USERS_PK' AS step,
  conname AS constraint_name
FROM pg_constraint con
JOIN pg_class rel ON rel.oid = con.conrelid
JOIN pg_namespace n ON n.oid = rel.relnamespace
WHERE n.nspname = 'auth' AND rel.relname = 'users' AND con.contype = 'p';
