-- =====================================================
-- FIX: Políticas RLS para Registro Público
-- =====================================================
-- Problema: Usuarios recién registrados no pueden insertar
-- en restaurants/accounts porque no están autenticados aún
-- Solución: Permitir INSERT si el user_id corresponde a un
-- usuario recién creado en auth.users
-- =====================================================

-- =====================================================
-- 1. RESTAURANTES - Permitir inserción durante registro
-- =====================================================

-- Eliminar política restrictiva existente
DROP POLICY IF EXISTS "restaurants_insert_own" ON public.restaurants;

-- Crear nueva política que permita registro público
CREATE POLICY "restaurants_insert_public_registration" ON public.restaurants
  FOR INSERT WITH CHECK (
    -- Permitir si el usuario está autenticado Y es su propio registro
    (auth.uid() IS NOT NULL AND user_id = auth.uid())
    OR
    -- O permitir si el user_id existe en auth.users (registro recién creado)
    (EXISTS (
      SELECT 1 FROM auth.users au
      WHERE au.id = user_id
    ))
  );

-- =====================================================
-- 2. ACCOUNTS - Permitir creación durante registro
-- =====================================================

-- Eliminar política restrictiva existente
DROP POLICY IF EXISTS "accounts_insert_system" ON public.accounts;

-- Crear nueva política que permita creación durante registro
CREATE POLICY "accounts_insert_public_registration" ON public.accounts
  FOR INSERT WITH CHECK (
    -- Permitir si el usuario está autenticado Y es su propia cuenta
    (auth.uid() IS NOT NULL AND user_id = auth.uid())
    OR
    -- O permitir si el user_id existe en auth.users (registro recién creado)
    (EXISTS (
      SELECT 1 FROM auth.users au
      WHERE au.id = user_id
    ))
  );

-- =====================================================
-- 3. USERS - Asegurar que usuarios puedan actualizar su perfil
-- =====================================================

-- La política de INSERT ya existe, pero agreguemos una para UPDATE durante registro
DROP POLICY IF EXISTS "users_update_own" ON public.users;

CREATE POLICY "users_update_own" ON public.users
  FOR UPDATE USING (
    -- Permitir si es el propio usuario
    id = auth.uid()
    OR
    -- O permitir si el usuario existe en auth.users (durante registro/verificación)
    (EXISTS (
      SELECT 1 FROM auth.users au
      WHERE au.id = id
    ))
  );

-- =====================================================
-- ✅ POLÍTICAS RLS ACTUALIZADAS PARA REGISTRO PÚBLICO
-- =====================================================

-- Verificar políticas creadas
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('restaurants', 'accounts', 'users')
ORDER BY tablename, cmd;
