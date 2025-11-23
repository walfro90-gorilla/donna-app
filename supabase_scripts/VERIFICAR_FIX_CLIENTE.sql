-- ============================================================================
-- VERIFICAR_FIX_CLIENTE.sql
-- ============================================================================
-- OBJETIVO: Verificar que el trigger fue creado correctamente
-- USO: Ejecutar DESPUÉS de FIX_CLIENT_SIGNUP_TRIGGER.sql
-- ============================================================================

-- ============================================================================
-- PARTE 1: VERIFICAR QUE EL TRIGGER EXISTE
-- ============================================================================

SELECT 
  '✅ TRIGGER VERIFICADO' as estado,
  t.tgname as trigger_name,
  n.nspname || '.' || c.relname as tabla,
  CASE t.tgtype::integer & 2
    WHEN 0 THEN 'BEFORE'
    ELSE 'AFTER'
  END as momento,
  CASE t.tgtype::integer & 4
    WHEN 4 THEN 'INSERT'
    ELSE 'OTHER'
  END as evento,
  p.proname as funcion_ejecutada
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE t.tgname = 'on_auth_user_created'
  AND n.nspname = 'auth'
  AND c.relname = 'users';


-- ============================================================================
-- PARTE 2: VERIFICAR QUE handle_new_user_signup_v2() EXISTE
-- ============================================================================

SELECT 
  '✅ FUNCIÓN VERIFICADA' as estado,
  p.proname as funcion,
  n.nspname as schema,
  pg_get_function_arguments(p.oid) as argumentos,
  pg_get_functiondef(p.oid) LIKE '%client_profiles%' as maneja_ubicacion
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'handle_new_user_signup_v2'
  AND n.nspname = 'public';


-- ============================================================================
-- PARTE 3: VERIFICAR QUE NO HAY FUNCIONES DUPLICADAS
-- ============================================================================

SELECT 
  CASE COUNT(*)
    WHEN 0 THEN '✅ SIN DUPLICADOS'
    ELSE '⚠️ HAY ' || COUNT(*) || ' DUPLICADOS'
  END as estado,
  COUNT(*) as total_versiones
FROM pg_proc
WHERE proname = 'ensure_user_profile_public'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');


-- ============================================================================
-- PARTE 4: VER ESTRUCTURA DE client_profiles
-- ============================================================================

SELECT 
  '📋 ESTRUCTURA DE client_profiles' as seccion,
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'client_profiles'
  AND column_name IN ('user_id', 'lat', 'lon', 'address', 'address_structured')
ORDER BY ordinal_position;


-- ============================================================================
-- PARTE 5: VER ÚLTIMO CLIENTE REGISTRADO
-- ============================================================================

SELECT 
  '🔍 ÚLTIMO CLIENTE' as seccion,
  u.id,
  u.email,
  u.name,
  u.phone,
  u.role,
  u.created_at,
  cp.lat,
  cp.lon,
  cp.address,
  CASE 
    WHEN cp.lat IS NOT NULL AND cp.lon IS NOT NULL THEN '✅ CON UBICACIÓN'
    ELSE '❌ SIN UBICACIÓN'
  END as estado_ubicacion
FROM public.users u
LEFT JOIN public.client_profiles cp ON u.id = cp.user_id
WHERE u.role = 'client'
ORDER BY u.created_at DESC
LIMIT 1;


-- ============================================================================
-- PARTE 6: CONTAR CLIENTES CON/SIN UBICACIÓN
-- ============================================================================

SELECT 
  '📊 ESTADÍSTICAS' as seccion,
  COUNT(*) FILTER (WHERE cp.lat IS NOT NULL AND cp.lon IS NOT NULL) as clientes_con_ubicacion,
  COUNT(*) FILTER (WHERE cp.lat IS NULL OR cp.lon IS NULL) as clientes_sin_ubicacion,
  COUNT(*) as total_clientes
FROM public.users u
LEFT JOIN public.client_profiles cp ON u.id = cp.user_id
WHERE u.role = 'client';


-- ============================================================================
-- PARTE 7: VER ÚLTIMOS LOGS DE SIGNUP
-- ============================================================================

SELECT 
  '📝 ÚLTIMOS LOGS' as seccion,
  source,
  event,
  role,
  user_id,
  email,
  details,
  created_at
FROM public.debug_user_signup_log
ORDER BY created_at DESC
LIMIT 5;


-- ============================================================================
-- RESULTADO ESPERADO:
-- ============================================================================
-- ✅ TRIGGER: on_auth_user_created existe en auth.users
-- ✅ FUNCIÓN: handle_new_user_signup_v2() existe en public
-- ✅ SIN DUPLICADOS: ensure_user_profile_public tiene 0 versiones
-- ✅ ESTRUCTURA: client_profiles tiene columnas lat, lon, address, address_structured
-- 
-- Después de crear un nuevo cliente:
-- ✅ ÚLTIMO CLIENTE: Debe tener name, phone, lat, lon
-- ✅ ESTADÍSTICAS: clientes_con_ubicacion debe incrementar
-- ✅ LOGS: Debe aparecer en debug_user_signup_log con todos los eventos
-- ============================================================================
