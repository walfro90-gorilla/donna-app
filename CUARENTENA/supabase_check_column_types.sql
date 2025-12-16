-- 🔍 VERIFICAR TIPOS DE COLUMNAS EXACTOS
-- Ejecuta este script para ver los tipos de datos reales

-- 1. Verificar tipo de 'id' en users
SELECT column_name, data_type, udt_name 
FROM information_schema.columns 
WHERE table_name = 'users' AND column_name = 'id';

-- 2. Verificar tipo de 'user_id' en restaurants  
SELECT column_name, data_type, udt_name 
FROM information_schema.columns 
WHERE table_name = 'restaurants' AND column_name = 'user_id';

-- 3. Verificar tipo de 'user_id' en orders
SELECT column_name, data_type, udt_name 
FROM information_schema.columns 
WHERE table_name = 'orders' AND column_name = 'user_id';

-- 4. Verificar qué retorna auth.uid()
SELECT pg_typeof(auth.uid()) as auth_uid_type;