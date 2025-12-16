-- Usuarios demo para probar navegación por roles
-- IMPORTANTE: Ejecutar este SQL en Supabase DESPUÉS de crear usuarios en Auth

-- Nota: Los usuarios deben crearse primero en Authentication > Users en Supabase Dashboard
-- Después ejecutar este script para crear los perfiles en la tabla 'users'

-- USUARIOS DEMO:
-- 1. cliente@demo.com - password: 123456
-- 2. restaurante@demo.com - password: 123456  
-- 3. repartidor@demo.com - password: 123456
-- 4. admin@demo.com - password: 123456

-- ===============================================
-- PERFIL DEMO: CLIENTE
-- ===============================================
INSERT INTO public.users (
    id, 
    email, 
    name, 
    phone, 
    address, 
    role, 
    email_confirm, 
    created_at, 
    updated_at
) VALUES (
    -- REEMPLAZAR ESTE UUID CON EL ID REAL DEL USUARIO DE AUTH
    '00000000-0000-0000-0000-000000000001', -- CAMBIAR POR ID REAL
    'cliente@demo.com',
    'Cliente Demo',
    '+57 300 123 4567',
    'Calle 123 #45-67, Bogotá',
    'cliente',
    true,
    now(),
    now()
) ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    name = EXCLUDED.name,
    phone = EXCLUDED.phone,
    address = EXCLUDED.address,
    role = EXCLUDED.role,
    email_confirm = EXCLUDED.email_confirm,
    updated_at = now();

-- ===============================================
-- PERFIL DEMO: RESTAURANTE
-- ===============================================
INSERT INTO public.users (
    id, 
    email, 
    name, 
    phone, 
    address, 
    role, 
    email_confirm, 
    created_at, 
    updated_at
) VALUES (
    -- REEMPLAZAR ESTE UUID CON EL ID REAL DEL USUARIO DE AUTH
    '00000000-0000-0000-0000-000000000002', -- CAMBIAR POR ID REAL
    'restaurante@demo.com',
    'Restaurante Demo',
    '+57 301 234 5678',
    'Carrera 456 #78-90, Bogotá',
    'restaurante',
    true,
    now(),
    now()
) ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    name = EXCLUDED.name,
    phone = EXCLUDED.phone,
    address = EXCLUDED.address,
    role = EXCLUDED.role,
    email_confirm = EXCLUDED.email_confirm,
    updated_at = now();

-- ===============================================
-- PERFIL DEMO: REPARTIDOR
-- ===============================================
INSERT INTO public.users (
    id, 
    email, 
    name, 
    phone, 
    address, 
    role, 
    email_confirm, 
    created_at, 
    updated_at
) VALUES (
    -- REEMPLAZAR ESTE UUID CON EL ID REAL DEL USUARIO DE AUTH
    '00000000-0000-0000-0000-000000000003', -- CAMBIAR POR ID REAL
    'repartidor@demo.com',
    'Repartidor Demo',
    '+57 302 345 6789',
    'Avenida 789 #12-34, Bogotá',
    'repartidor',
    true,
    now(),
    now()
) ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    name = EXCLUDED.name,
    phone = EXCLUDED.phone,
    address = EXCLUDED.address,
    role = EXCLUDED.role,
    email_confirm = EXCLUDED.email_confirm,
    updated_at = now();

-- ===============================================
-- PERFIL DEMO: ADMIN
-- ===============================================
INSERT INTO public.users (
    id, 
    email, 
    name, 
    phone, 
    address, 
    role, 
    email_confirm, 
    created_at, 
    updated_at
) VALUES (
    -- REEMPLAZAR ESTE UUID CON EL ID REAL DEL USUARIO DE AUTH
    '00000000-0000-0000-0000-000000000004', -- CAMBIAR POR ID REAL
    'admin@demo.com',
    'Administrador Demo',
    '+57 303 456 7890',
    'Plaza Central #56-78, Bogotá',
    'admin',
    true,
    now(),
    now()
) ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    name = EXCLUDED.name,
    phone = EXCLUDED.phone,
    address = EXCLUDED.address,
    role = EXCLUDED.role,
    email_confirm = EXCLUDED.email_confirm,
    updated_at = now();

-- ===============================================
-- INSTRUCCIONES:
-- ===============================================
/*
1. Ve a Supabase Dashboard > Authentication > Users
2. Crea manualmente estos 4 usuarios:
   - cliente@demo.com (password: 123456)
   - restaurante@demo.com (password: 123456)
   - repartidor@demo.com (password: 123456)
   - admin@demo.com (password: 123456)

3. Después de crear cada usuario, copia su UUID desde Auth
4. Reemplaza los UUIDs de este script con los IDs reales
5. Ejecuta este script en SQL Editor

Alternativamente, puedes usar el trigger automático:
- Registra cada usuario normalmente desde la app
- El trigger creará automáticamente el perfil con rol 'cliente'
- Después cambia manualmente los roles en la tabla 'users'
*/