-- ============================================================================
-- CONSULTA: VER LOGS DE CONFIRMACIÓN DE EMAIL
-- ============================================================================
-- Usa este script para monitorear el proceso de confirmación de email
-- y debug si algo falla
-- ============================================================================

SELECT '🔍 ============= DIAGNÓSTICO EMAIL CONFIRMATION =============' as info;

-- ============================================================================
-- 1. VERIFICAR SI LA TABLA DE LOGS EXISTE
-- ============================================================================

SELECT 
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_name = 'function_logs'
    ) 
    THEN '✅ Tabla function_logs existe'
    ELSE '❌ Tabla function_logs NO existe - ejecuta NUCLEAR_FIX_EMAIL_CONFIRMATION.sql primero'
  END as estado_tabla_logs;

-- ============================================================================
-- 2. VER ÚLTIMOS 20 LOGS DEL TRIGGER
-- ============================================================================

SELECT '📋 ÚLTIMOS 20 LOGS DEL TRIGGER handle_email_confirmed:' as titulo;

SELECT 
  id,
  level,
  message,
  metadata->>'user_id' as user_id,
  metadata->>'email' as email,
  metadata->>'error' as error,
  created_at,
  metadata
FROM public.function_logs
WHERE function_name = 'handle_email_confirmed'
ORDER BY created_at DESC
LIMIT 20;

-- ============================================================================
-- 3. VER SOLO ERRORES
-- ============================================================================

SELECT '🚨 LOGS DE ERROR (level = ERROR o CRITICAL):' as titulo;

SELECT 
  id,
  level,
  message,
  metadata->>'user_id' as user_id,
  metadata->>'email' as email,
  metadata->>'error' as error_detail,
  metadata->>'sqlstate' as sqlstate,
  created_at
FROM public.function_logs
WHERE function_name = 'handle_email_confirmed'
  AND level IN ('ERROR', 'CRITICAL')
ORDER BY created_at DESC
LIMIT 10;

-- ============================================================================
-- 4. VER LOGS DE ÚLTIMOS 5 MINUTOS
-- ============================================================================

SELECT '⏱️ LOGS DE ÚLTIMOS 5 MINUTOS:' as titulo;

SELECT 
  id,
  level,
  message,
  metadata->>'user_id' as user_id,
  metadata->>'email' as email,
  created_at
FROM public.function_logs
WHERE function_name = 'handle_email_confirmed'
  AND created_at > now() - interval '5 minutes'
ORDER BY created_at DESC;

-- ============================================================================
-- 5. VERIFICAR ESTADO DE USUARIOS PENDIENTES DE CONFIRMACIÓN
-- ============================================================================

SELECT '👥 USUARIOS PENDIENTES DE CONFIRMACIÓN EMAIL:' as titulo;

SELECT 
  au.id,
  au.email,
  au.created_at as auth_created,
  au.email_confirmed_at,
  pu.email_confirm as public_email_confirm,
  pu.created_at as public_created
FROM auth.users au
LEFT JOIN public.users pu ON pu.id = au.id
WHERE au.email_confirmed_at IS NULL
ORDER BY au.created_at DESC
LIMIT 10;

-- ============================================================================
-- 6. VERIFICAR USUARIOS RECIENTEMENTE CONFIRMADOS
-- ============================================================================

SELECT '✅ USUARIOS CONFIRMADOS EN ÚLTIMAS 24 HORAS:' as titulo;

SELECT 
  au.id,
  au.email,
  au.email_confirmed_at as auth_confirmed,
  pu.email_confirm as public_confirmed,
  pu.updated_at as public_updated,
  CASE 
    WHEN pu.email_confirm = true THEN '✅ Sincronizado'
    ELSE '⚠️ Desincronizado'
  END as sync_status
FROM auth.users au
LEFT JOIN public.users pu ON pu.id = au.id
WHERE au.email_confirmed_at > now() - interval '24 hours'
ORDER BY au.email_confirmed_at DESC;

-- ============================================================================
-- 7. VERIFICAR QUE EL TRIGGER EXISTE Y ESTÁ ACTIVO
-- ============================================================================

SELECT '🔧 ESTADO DEL TRIGGER:' as titulo;

SELECT 
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  tgenabled as status,
  CASE tgenabled
    WHEN 'O' THEN '✅ Enabled'
    WHEN 'D' THEN '❌ Disabled'
    WHEN 'R' THEN '🔧 Replica only'
    WHEN 'A' THEN '🔧 Always'
    ELSE '❓ Unknown'
  END as status_description,
  pg_get_triggerdef(oid) as trigger_definition
FROM pg_trigger
WHERE tgname = 'on_auth_user_email_confirmed'
  AND tgrelid = 'auth.users'::regclass;

-- ============================================================================
-- 8. VERIFICAR PERMISOS DE LA FUNCIÓN
-- ============================================================================

SELECT '🔐 PERMISOS DE handle_email_confirmed():' as titulo;

SELECT 
  proname as function_name,
  prosecdef as security_definer,
  proowner::regrole as owner,
  proacl as permissions
FROM pg_proc
WHERE proname = 'handle_email_confirmed'
  AND pronamespace = 'public'::regnamespace;

-- ============================================================================
-- 9. RESUMEN ESTADÍSTICO
-- ============================================================================

SELECT '📊 RESUMEN ESTADÍSTICO:' as titulo;

SELECT 
  COUNT(*) FILTER (WHERE au.email_confirmed_at IS NULL) as pendientes_confirmacion,
  COUNT(*) FILTER (WHERE au.email_confirmed_at IS NOT NULL) as confirmados,
  COUNT(*) FILTER (WHERE au.email_confirmed_at IS NOT NULL AND pu.email_confirm = true) as sincronizados_correctamente,
  COUNT(*) FILTER (WHERE au.email_confirmed_at IS NOT NULL AND (pu.email_confirm IS NULL OR pu.email_confirm = false)) as desincronizados,
  COUNT(*) FILTER (WHERE au.created_at > now() - interval '1 hour') as nuevos_ultima_hora,
  COUNT(*) FILTER (WHERE au.email_confirmed_at > now() - interval '1 hour') as confirmados_ultima_hora
FROM auth.users au
LEFT JOIN public.users pu ON pu.id = au.id;

-- ============================================================================
-- RESUMEN
-- ============================================================================

SELECT '
╔═══════════════════════════════════════════════════════════════════╗
║              📋 CÓMO INTERPRETAR ESTOS RESULTADOS                 ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  ✅ NORMAL:                                                       ║
║     - Tabla function_logs existe                                  ║
║     - Trigger está activo (status = O)                           ║
║     - Logs muestran "Email confirmed successfully"               ║
║     - Usuarios confirmados tienen email_confirm = true           ║
║                                                                   ║
║  ⚠️  PROBLEMAS COMUNES:                                           ║
║     - Logs muestran ERROR: revisar metadata->error               ║
║     - Trigger disabled: ejecutar NUCLEAR_FIX nuevamente         ║
║     - Usuarios desincronizados: el trigger no está corriendo    ║
║                                                                   ║
║  🔧 SOLUCIÓN:                                                     ║
║     Si hay errores, ejecuta:                                     ║
║     NUCLEAR_FIX_EMAIL_CONFIRMATION.sql                           ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
' as guia;
