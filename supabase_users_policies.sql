-- 👤 POLÍTICAS PARA TABLA USERS

-- Habilitar RLS para users
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- 📖 Política de LECTURA: Solo puede leer su propio perfil
CREATE POLICY "users_read_own" 
ON users FOR SELECT 
USING (id = auth.uid());

-- ✏️ Política de ACTUALIZACIÓN: Solo puede actualizar su propio perfil
CREATE POLICY "users_update_own" 
ON users FOR UPDATE 
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- ➕ Política de INSERCIÓN: Puede crear su propio perfil
CREATE POLICY "users_insert_own" 
ON users FOR INSERT 
WITH CHECK (id = auth.uid());