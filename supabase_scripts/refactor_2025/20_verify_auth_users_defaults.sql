-- ============================================================================
-- 20_verify_auth_users_defaults.sql
-- Propósito: Verificar que auth.users.id tiene default y PK después del fix.
-- ============================================================================

-- 1) Ver defaults y nullability de columnas clave
SELECT 'COLUMNS' AS section,
       column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'auth'
  AND table_name   = 'users'
  AND column_name IN ('id', 'email', 'created_at', 'updated_at', 'raw_app_meta_data', 'raw_user_meta_data')
ORDER BY column_name;

-- 2) Ver PK
SELECT 'PRIMARY_KEY' AS section,
       conname AS constraint_name,
       pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint con
JOIN pg_class rel ON rel.oid = con.conrelid
JOIN pg_namespace n ON n.oid = rel.relnamespace
WHERE n.nspname = 'auth' AND rel.relname = 'users' AND con.contype = 'p';

-- 3) Mostrar expresión exacta del default de id
SELECT 'ID_DEFAULT_EXPR' AS section,
       pg_get_expr(d.adbin, d.adrelid) AS id_default_expr
FROM pg_attrdef d
JOIN pg_class c ON c.oid = d.adrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = d.adnum
WHERE n.nspname = 'auth' AND c.relname = 'users' AND a.attname = 'id';
