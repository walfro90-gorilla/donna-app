-- ============================================================================
-- PASO 2: CREAR POLÍTICAS SOLO PARA TABLA USERS
-- ============================================================================

-- Habilitar RLS en la tabla users
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Política 1: Los usuarios pueden ver su propio perfil
CREATE POLICY "users_own_profile" ON users
    FOR SELECT
    USING (id = auth.uid());

-- Política 2: Los usuarios pueden actualizar su propio perfil
CREATE POLICY "users_update_own" ON users
    FOR UPDATE
    USING (id = auth.uid());

-- Política 3: Permitir insertar nuevos usuarios (registro)
CREATE POLICY "users_insert_own" ON users
    FOR INSERT
    WITH CHECK (id = auth.uid());

-- Verificar que las políticas se crearon correctamente
SELECT 
    schemaname,
    tablename,
    policyname,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'users'
ORDER BY tablename, policyname;