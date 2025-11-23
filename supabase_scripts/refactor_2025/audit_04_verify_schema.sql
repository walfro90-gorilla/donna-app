-- =====================================================================
-- AUDITORÍA FASE 1.4: VERIFICACIÓN DE ESQUEMA DE TABLAS CRÍTICAS
-- =====================================================================
-- Descripción:
--   Verifica que el esquema real de la base de datos coincida con
--   DATABASE_SCHEMA.sql para las tablas críticas de signup/profiles
--
-- Tablas a verificar:
--   - auth.users
--   - public.users
--   - public.client_profiles
--   - public.delivery_agent_profiles
--   - public.restaurants
--
-- Uso:
--   Ejecutar en SQL Editor de Supabase
--   Copiar el resultado completo
-- =====================================================================

-- PASO 1: Verificar estructura de auth.users
SELECT
  '1_AUTH_USERS_COLUMNS' AS step,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'auth'
  AND table_name = 'users'
ORDER BY ordinal_position;

-- PASO 2: Verificar estructura de public.users
SELECT
  '2_PUBLIC_USERS_COLUMNS' AS step,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'users'
ORDER BY ordinal_position;

-- PASO 3: Verificar estructura de public.client_profiles
SELECT
  '3_CLIENT_PROFILES_COLUMNS' AS step,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'client_profiles'
ORDER BY ordinal_position;

-- PASO 4: Verificar estructura de public.delivery_agent_profiles
SELECT
  '4_DELIVERY_AGENT_PROFILES_COLUMNS' AS step,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'delivery_agent_profiles'
ORDER BY ordinal_position;

-- PASO 5: Verificar estructura de public.restaurants
SELECT
  '5_RESTAURANTS_COLUMNS' AS step,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'restaurants'
ORDER BY ordinal_position;

-- PASO 6: Verificar foreign keys
SELECT
  '6_FOREIGN_KEYS' AS step,
  tc.table_schema,
  tc.table_name,
  kcu.column_name,
  ccu.table_schema AS foreign_table_schema,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name,
  tc.constraint_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
  AND tc.table_name IN ('users', 'client_profiles', 'delivery_agent_profiles', 'restaurants')
ORDER BY tc.table_name, tc.constraint_name;

-- =====================================================================
-- RESULTADO ESPERADO:
-- - Estructura completa de las tablas críticas
-- - Verificar que users.id → auth.users.id
-- - Verificar que profiles.user_id → users.id
-- - Identificar discrepancias con DATABASE_SCHEMA.sql
-- =====================================================================
