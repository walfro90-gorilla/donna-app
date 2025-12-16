-- 🔍 VERIFICAR TIPOS EXACTOS DE TODAS LAS COLUMNAS
-- Ejecuta esto para ver los tipos reales de tus tablas

-- Verificar tabla users
SELECT 
    column_name, 
    data_type, 
    udt_name,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'users' 
ORDER BY ordinal_position;

-- Verificar tabla restaurants  
SELECT 
    column_name, 
    data_type, 
    udt_name,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'restaurants' 
ORDER BY ordinal_position;

-- Verificar tabla orders
SELECT 
    column_name, 
    data_type, 
    udt_name,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'orders' 
ORDER BY ordinal_position;

-- Verificar tabla order_items
SELECT 
    column_name, 
    data_type, 
    udt_name,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'order_items' 
ORDER BY ordinal_position;

-- También verificar el tipo que retorna auth.uid()
SELECT pg_typeof(auth.uid()) as auth_uid_type;