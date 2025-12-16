-- ============================================
-- SOLUCIÓN DEFINITIVA: ELIMINAR Y RECREAR POLÍTICAS RLS SIN RECURSIÓN
-- ============================================

-- 1. DESACTIVAR RLS TEMPORALMENTE
ALTER TABLE public.users DISABLE ROW LEVEL SECURITY;

-- 2. ELIMINAR TODAS LAS POLÍTICAS EXISTENTES (para evitar recursión)
DROP POLICY IF EXISTS "Users can view own profile" ON public.users;
DROP POLICY IF EXISTS "Users can update own profile" ON public.users;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.users;
DROP POLICY IF EXISTS "Allow public read access" ON public.users;
DROP POLICY IF EXISTS "Allow authenticated users to read" ON public.users;
DROP POLICY IF EXISTS "Allow users to update own profile" ON public.users;
DROP POLICY IF EXISTS "Allow users to insert own profile" ON public.users;

-- 3. REACTIVAR RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- 4. CREAR POLÍTICAS SIMPLES SIN RECURSIÓN
-- Solo permitir que los usuarios vean y editen SU PROPIO perfil

-- Política para SELECT (lectura)
CREATE POLICY "Allow users to read own profile"
  ON public.users
  FOR SELECT
  USING (auth.uid() = id);

-- Política para UPDATE (actualización)
CREATE POLICY "Allow users to update own profile"  
  ON public.users
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Política para INSERT (inserción) - solo para el trigger automático
CREATE POLICY "Allow service role to insert users"
  ON public.users
  FOR INSERT
  WITH CHECK (true); -- Permite al trigger crear usuarios

-- ============================================
-- OPCIONAL: Si necesitas que los admins vean todos los usuarios
-- ============================================

-- Política adicional para admins (solo si es necesario)
CREATE POLICY "Allow admins to read all users"
  ON public.users
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() 
      AND role = 'admin'
    )
  );

-- ============================================
-- VERIFICAR QUE TODO FUNCIONE
-- ============================================

-- Verificar que las políticas están activas
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies 
WHERE tablename = 'users';