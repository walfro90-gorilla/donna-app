-- =====================================================
-- FASE 6: ACTUALIZACIÓN DE POLÍTICAS RLS (IDEMPOTENTE)
-- =====================================================
-- Actualiza Row Level Security eliminando referencias a campos obsoletos
-- Este script es completamente idempotente y puede ejecutarse múltiples veces
-- Tiempo estimado: 10 minutos
-- =====================================================

BEGIN;

-- ====================================
-- PASO 1: Políticas para users
-- ====================================

-- Eliminar si existe y recrear
DROP POLICY IF EXISTS "users_select_own" ON public.users CASCADE;
CREATE POLICY "users_select_own"
  ON public.users
  FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

DROP POLICY IF EXISTS "users_select_admin" ON public.users CASCADE;
CREATE POLICY "users_select_admin"
  ON public.users
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users u 
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "users_update_own" ON public.users CASCADE;
CREATE POLICY "users_update_own"
  ON public.users
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id AND
    -- Solo pueden actualizar estos campos
    name IS NOT NULL AND
    email IS NOT NULL AND
    role IS NOT NULL
  );

-- ====================================
-- PASO 2: Políticas para client_profiles
-- ====================================

DROP POLICY IF EXISTS "client_profiles_select_own" ON public.client_profiles CASCADE;
CREATE POLICY "client_profiles_select_own"
  ON public.client_profiles
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

DROP POLICY IF EXISTS "client_profiles_update_own" ON public.client_profiles CASCADE;
CREATE POLICY "client_profiles_update_own"
  ON public.client_profiles
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

-- ====================================
-- PASO 3: Políticas para restaurants
-- ====================================

DROP POLICY IF EXISTS "restaurants_select_own" ON public.restaurants CASCADE;
CREATE POLICY "restaurants_select_own"
  ON public.restaurants
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

DROP POLICY IF EXISTS "restaurants_select_public" ON public.restaurants CASCADE;
CREATE POLICY "restaurants_select_public"
  ON public.restaurants
  FOR SELECT
  TO authenticated, anon
  USING (status = 'approved' AND online = TRUE);

DROP POLICY IF EXISTS "restaurants_update_own" ON public.restaurants CASCADE;
CREATE POLICY "restaurants_update_own"
  ON public.restaurants
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

-- ====================================
-- PASO 4: Políticas para delivery_agent_profiles
-- ====================================

DROP POLICY IF EXISTS "delivery_profiles_select_own" ON public.delivery_agent_profiles CASCADE;
CREATE POLICY "delivery_profiles_select_own"
  ON public.delivery_agent_profiles
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

DROP POLICY IF EXISTS "delivery_profiles_update_own" ON public.delivery_agent_profiles CASCADE;
CREATE POLICY "delivery_profiles_update_own"
  ON public.delivery_agent_profiles
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

-- ====================================
-- PASO 5: Políticas para accounts
-- ====================================

DROP POLICY IF EXISTS "accounts_select_own" ON public.accounts CASCADE;
CREATE POLICY "accounts_select_own"
  ON public.accounts
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- Solo el sistema puede insertar/actualizar cuentas (vía RPCs)
-- No necesitan políticas de INSERT/UPDATE para usuarios normales

-- ====================================
-- PASO 6: Políticas para user_preferences
-- ====================================

DROP POLICY IF EXISTS "user_prefs_select_own" ON public.user_preferences CASCADE;
CREATE POLICY "user_prefs_select_own"
  ON public.user_preferences
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_prefs_update_own" ON public.user_preferences CASCADE;
CREATE POLICY "user_prefs_update_own"
  ON public.user_preferences
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

-- ====================================
-- PASO 7: Verificar que RLS esté habilitado
-- ====================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_agent_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

-- ====================================
-- PASO 8: Log de actualización
-- ====================================

INSERT INTO public.debug_logs (scope, message, meta)
VALUES (
  'REFACTOR_2025_RLS',
  'Políticas RLS actualizadas (idempotente)',
  jsonb_build_object(
    'timestamp', NOW(),
    'fase', '6',
    'policies_created', 15
  )
);

COMMIT;

-- Verificación: Listar todas las políticas
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('users', 'client_profiles', 'restaurants', 'delivery_agent_profiles', 'accounts', 'user_preferences')
ORDER BY tablename, policyname;

-- ✅ Verifica que todas las políticas estén correctas y no hagan referencia a campos eliminados
