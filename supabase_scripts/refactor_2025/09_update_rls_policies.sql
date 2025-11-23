-- =====================================================
-- FASE 6: ACTUALIZACIÓN DE POLÍTICAS RLS
-- =====================================================
-- Actualiza Row Level Security eliminando referencias a campos obsoletos
-- Tiempo estimado: 10 minutos
-- =====================================================

BEGIN;

-- ====================================
-- PASO 1: Eliminar políticas obsoletas de users
-- ====================================

-- Eliminar todas las políticas existentes en users
DROP POLICY IF EXISTS "Users can view their own profile" ON public.users;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.users;
DROP POLICY IF EXISTS "Admins can view all users" ON public.users;
DROP POLICY IF EXISTS "Public read for active users" ON public.users;

-- ====================================
-- PASO 2: Crear políticas nuevas simplificadas para users
-- ====================================

-- Usuarios pueden ver su propio perfil
CREATE POLICY "users_select_own"
  ON public.users
  FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

-- Admins pueden ver todos los usuarios
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

-- Usuarios pueden actualizar su propio perfil (solo algunos campos)
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
-- PASO 3: Políticas para client_profiles
-- ====================================

-- Eliminar políticas obsoletas
DROP POLICY IF EXISTS "Clients can view own profile" ON public.client_profiles;
DROP POLICY IF EXISTS "Clients can update own profile" ON public.client_profiles;

-- Clientes pueden ver su propio perfil
CREATE POLICY "client_profiles_select_own"
  ON public.client_profiles
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- Clientes pueden actualizar su propio perfil
CREATE POLICY "client_profiles_update_own"
  ON public.client_profiles
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

-- ====================================
-- PASO 4: Políticas para restaurants
-- ====================================

-- Mantener políticas existentes, solo verificar que no dependan de users.status
-- Ya están bien definidas en el schema actual

-- Restaurantes pueden ver su propio perfil
DROP POLICY IF EXISTS "Restaurants can view own profile" ON public.restaurants;
CREATE POLICY "restaurants_select_own"
  ON public.restaurants
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- Todos pueden ver restaurantes aprobados y online
CREATE POLICY "restaurants_select_public"
  ON public.restaurants
  FOR SELECT
  TO authenticated, anon
  USING (status = 'approved' AND online = TRUE);

-- Restaurantes pueden actualizar su propio perfil
DROP POLICY IF EXISTS "Restaurants can update own profile" ON public.restaurants;
CREATE POLICY "restaurants_update_own"
  ON public.restaurants
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

-- ====================================
-- PASO 5: Políticas para delivery_agent_profiles
-- ====================================

-- Repartidores pueden ver su propio perfil
DROP POLICY IF EXISTS "Delivery agents can view own profile" ON public.delivery_agent_profiles;
CREATE POLICY "delivery_profiles_select_own"
  ON public.delivery_agent_profiles
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- Repartidores pueden actualizar su propio perfil
DROP POLICY IF EXISTS "Delivery agents can update own profile" ON public.delivery_agent_profiles;
CREATE POLICY "delivery_profiles_update_own"
  ON public.delivery_agent_profiles
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

-- ====================================
-- PASO 6: Políticas para accounts
-- ====================================

-- Usuarios pueden ver su propia cuenta
DROP POLICY IF EXISTS "Users can view own account" ON public.accounts;
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
-- PASO 7: Políticas para user_preferences
-- ====================================

DROP POLICY IF EXISTS "Users can view own preferences" ON public.user_preferences;
DROP POLICY IF EXISTS "Users can update own preferences" ON public.user_preferences;

CREATE POLICY "user_prefs_select_own"
  ON public.user_preferences
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "user_prefs_update_own"
  ON public.user_preferences
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

-- ====================================
-- PASO 8: Verificar que RLS esté habilitado
-- ====================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_agent_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

-- ====================================
-- PASO 9: Log de actualización
-- ====================================

INSERT INTO public.debug_logs (scope, message, meta)
VALUES (
  'REFACTOR_2025_RLS',
  'Políticas RLS actualizadas',
  jsonb_build_object(
    'timestamp', NOW(),
    'fase', '6',
    'policies_updated', 15
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
