-- =====================================================================
-- 10_test_registrations_CORREGIDO.sql
-- =====================================================================
-- Tests para verificar las funciones de registro
-- IMPORTANTE: Este script NO puede ejecutarse directamente en SQL Editor
-- porque las funciones requieren auth.uid() que solo existe en contexto
-- de una sesión autenticada desde el cliente (Flutter/Supabase)
--
-- USO CORRECTO:
-- 1. Desde tu app Flutter, llama a las funciones después de signUp
-- 2. O usa Supabase Dashboard > SQL Editor > "Run as authenticated user"
-- =====================================================================

-- ====================================
-- VERIFICACIÓN: Funciones creadas
-- ====================================
SELECT 
  '🔍 VERIFICACIÓN: Funciones de registro creadas' as etapa;

SELECT 
  p.proname as function_name,
  pg_catalog.pg_get_function_arguments(p.oid) as arguments,
  pg_catalog.pg_get_function_result(p.oid) as return_type,
  p.prosecdef as is_security_definer
FROM pg_catalog.pg_proc p
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('register_client', 'register_restaurant', 'register_delivery_agent')
ORDER BY p.proname;

-- ====================================
-- VERIFICACIÓN: Tablas necesarias existen
-- ====================================
SELECT 
  '🔍 VERIFICACIÓN: Tablas necesarias' as etapa;

SELECT 
  table_name,
  CASE 
    WHEN table_name IN ('users', 'client_profiles', 'restaurants', 'delivery_agent_profiles', 'user_preferences', 'accounts', 'admin_notifications') 
    THEN '✅ Existe'
    ELSE '❌ Falta'
  END as status
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('users', 'client_profiles', 'restaurants', 'delivery_agent_profiles', 'user_preferences', 'accounts', 'admin_notifications')
ORDER BY table_name;

-- ====================================
-- VERIFICACIÓN: Columnas críticas en users
-- ====================================
SELECT 
  '🔍 VERIFICACIÓN: Columnas en public.users' as etapa;

SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'users'
ORDER BY ordinal_position;

-- ====================================
-- VERIFICACIÓN: Foreign keys
-- ====================================
SELECT 
  '🔍 VERIFICACIÓN: Foreign Keys' as etapa;

SELECT 
  tc.table_name, 
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc 
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY' 
  AND tc.table_schema = 'public'
  AND tc.table_name IN ('client_profiles', 'restaurants', 'delivery_agent_profiles', 'user_preferences', 'accounts')
ORDER BY tc.table_name;

-- ====================================
-- NOTA IMPORTANTE
-- ====================================
SELECT 
  '⚠️  IMPORTANTE: CÓMO PROBAR LAS FUNCIONES' as nota,
  '
  Las funciones register_* requieren auth.uid() que solo está disponible
  en contexto autenticado. Para probarlas:
  
  OPCIÓN 1 - Desde Flutter:
  ───────────────────────────
  final response = await supabase.auth.signUp(
    email: "test@example.com",
    password: "password123"
  );
  
  if (response.user != null) {
    final result = await supabase.rpc("register_client", params: {
      "p_email": "test@example.com",
      "p_password": "password123",
      "p_name": "Test User",
      "p_phone": "+1234567890",
      "p_address": "123 Main St",
      "p_lat": 19.4326,
      "p_lon": -99.1332,
      "p_address_structured": {"city": "CDMX", "country": "México"}
    });
    print(result);
  }
  
  OPCIÓN 2 - Supabase Dashboard:
  ───────────────────────────────
  1. Crea un usuario de prueba en Authentication
  2. SQL Editor > "Run as authenticated user" (dropdown)
  3. Selecciona el usuario de prueba
  4. Ejecuta: SELECT public.register_client(...);
  
  OPCIÓN 3 - Crear trigger automático (RECOMENDADO):
  ───────────────────────────────────────────────────
  Ver script: 12_create_auto_registration_trigger.sql
  ' as instrucciones;

-- ====================================
-- EJEMPLO DE QUERIES PARA VERIFICAR DATOS
-- ====================================
-- Una vez que hayas registrado usuarios desde la app,
-- puedes verificar los datos con estas queries:

-- Ver usuarios creados
-- SELECT id, email, name, phone, role, email_confirm, created_at FROM public.users ORDER BY created_at DESC LIMIT 10;

-- Ver perfiles de clientes
-- SELECT user_id, address, lat, lon, created_at FROM public.client_profiles ORDER BY created_at DESC LIMIT 10;

-- Ver restaurantes
-- SELECT id, user_id, name, status, address, phone, created_at FROM public.restaurants ORDER BY created_at DESC LIMIT 10;

-- Ver repartidores
-- SELECT user_id, vehicle_type, status, account_state, created_at FROM public.delivery_agent_profiles ORDER BY created_at DESC LIMIT 10;

-- Ver notificaciones de admin
-- SELECT title, message, entity_type, metadata, created_at FROM public.admin_notifications ORDER BY created_at DESC LIMIT 10;
