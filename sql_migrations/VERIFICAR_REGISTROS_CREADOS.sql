-- ============================================================================
-- VERIFICAR REGISTROS CREADOS - Registro de Restaurantes
-- ============================================================================
-- 🎯 Usa este script para verificar QUÉ DATOS se guardaron realmente
-- 
-- Copia y pega en Supabase SQL Editor para ver:
-- 1. Usuarios creados (public.users)
-- 2. Restaurantes creados (public.restaurants)
-- 3. Cuentas financieras creadas (public.accounts)
-- ============================================================================

-- ============================================================================
-- CONSULTA 1: Últimos 5 usuarios creados
-- ============================================================================
SELECT 
  '👤 USUARIOS CREADOS (public.users)' as "Tabla",
  id,
  email,
  name,
  phone,
  role,
  address,
  created_at
FROM public.users
ORDER BY created_at DESC
LIMIT 5;

-- ============================================================================
-- CONSULTA 2: Últimos 5 restaurantes creados
-- ============================================================================
SELECT 
  '🍽️ RESTAURANTES CREADOS (public.restaurants)' as "Tabla",
  id,
  user_id,
  name,
  phone,
  address,
  location_lat,
  location_lon,
  status,
  online,
  created_at
FROM public.restaurants
ORDER BY created_at DESC
LIMIT 5;

-- ============================================================================
-- CONSULTA 3: Últimas 5 cuentas financieras creadas
-- ============================================================================
SELECT 
  '💰 CUENTAS CREADAS (public.accounts)' as "Tabla",
  id,
  user_id,
  account_type,
  balance,
  created_at
FROM public.accounts
ORDER BY created_at DESC
LIMIT 5;

-- ============================================================================
-- CONSULTA 4: JOIN completo - Ver relaciones entre tablas
-- ============================================================================
SELECT 
  '🔗 DATOS COMPLETOS DEL ÚLTIMO RESTAURANTE' as "Información",
  u.id as user_id,
  u.email as user_email,
  u.name as owner_name,
  u.role as user_role,
  r.id as restaurant_id,
  r.name as restaurant_name,
  r.status as restaurant_status,
  r.phone as restaurant_phone,
  r.address as restaurant_address,
  a.id as account_id,
  a.account_type,
  a.balance,
  r.created_at
FROM public.users u
LEFT JOIN public.restaurants r ON r.user_id = u.id
LEFT JOIN public.accounts a ON a.user_id = u.id
WHERE u.role = 'restaurant'
ORDER BY r.created_at DESC
LIMIT 1;

-- ============================================================================
-- CONSULTA 5: Contar registros por tipo
-- ============================================================================
SELECT 
  'RESUMEN GENERAL' as "Estadísticas",
  (SELECT COUNT(*) FROM public.users WHERE role = 'restaurant') as total_usuarios_restaurant,
  (SELECT COUNT(*) FROM public.restaurants) as total_restaurantes,
  (SELECT COUNT(*) FROM public.accounts WHERE account_type = 'restaurant') as total_cuentas_restaurant;

-- ============================================================================
-- FIN
-- ============================================================================
