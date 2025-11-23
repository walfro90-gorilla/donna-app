-- ============================================================================
-- VERIFICAR user_preferences - Después del registro de restaurante
-- ============================================================================
-- 🎯 Usa este script para confirmar que user_preferences se está creando
-- 
-- Copia y pega en Supabase SQL Editor DESPUÉS de registrar un restaurante
-- ============================================================================

-- ============================================================================
-- CONSULTA 1: Ver user_preferences del último restaurante registrado
-- ============================================================================
SELECT 
  '🔍 USER PREFERENCES - Último Restaurante' as "Estado",
  up.user_id,
  u.email,
  u.name,
  u.role,
  up.restaurant_id,
  r.name as restaurant_name,
  up.has_seen_onboarding,
  up.has_seen_restaurant_welcome,
  up.email_verified_congrats_shown,
  up.first_login_at,
  up.last_login_at,
  up.login_count,
  up.created_at,
  up.updated_at
FROM public.user_preferences up
JOIN public.users u ON u.id = up.user_id
LEFT JOIN public.restaurants r ON r.id = up.restaurant_id
WHERE u.role = 'restaurant'
ORDER BY up.created_at DESC
LIMIT 1;

-- ============================================================================
-- CONSULTA 2: Contar registros de user_preferences por rol
-- ============================================================================
SELECT 
  '📊 RESUMEN user_preferences' as "Estadísticas",
  u.role,
  COUNT(up.user_id) as total_registros,
  SUM(CASE WHEN up.restaurant_id IS NOT NULL THEN 1 ELSE 0 END) as con_restaurant_id
FROM public.users u
LEFT JOIN public.user_preferences up ON up.user_id = u.id
WHERE u.role IN ('restaurant', 'delivery_agent', 'client')
GROUP BY u.role
ORDER BY u.role;

-- ============================================================================
-- CONSULTA 3: Ver usuarios restaurant SIN user_preferences (debería estar vacío)
-- ============================================================================
SELECT 
  '⚠️  RESTAURANTES SIN user_preferences' as "Problema",
  u.id as user_id,
  u.email,
  u.name,
  u.role,
  u.created_at,
  'FALTA CREAR user_preferences' as status
FROM public.users u
WHERE u.role = 'restaurant'
  AND NOT EXISTS (
    SELECT 1 FROM public.user_preferences up 
    WHERE up.user_id = u.id
  )
ORDER BY u.created_at DESC
LIMIT 5;

-- ============================================================================
-- CONSULTA 4: Ver datos completos del último restaurante (JOIN total)
-- ============================================================================
SELECT 
  '✅ REGISTRO COMPLETO - Último Restaurante' as "Información",
  u.id as user_id,
  u.email,
  u.name as owner_name,
  u.role,
  r.id as restaurant_id,
  r.name as restaurant_name,
  r.status as restaurant_status,
  a.id as account_id,
  a.balance,
  up.user_id as preferences_exist,
  CASE 
    WHEN up.user_id IS NOT NULL THEN '✅ Creado'
    ELSE '❌ Falta'
  END as user_preferences_status,
  r.created_at
FROM public.users u
LEFT JOIN public.restaurants r ON r.user_id = u.id
LEFT JOIN public.accounts a ON a.user_id = u.id
LEFT JOIN public.user_preferences up ON up.user_id = u.id
WHERE u.role = 'restaurant'
ORDER BY r.created_at DESC
LIMIT 1;

-- ============================================================================
-- FIN
-- ============================================================================
