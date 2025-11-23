-- =====================================================
-- FASE 1: LIMPIEZA DE DATOS DE PRUEBA
-- =====================================================
-- Propósito: Eliminar datos de prueba para migración limpia
-- Orden: Debe ejecutarse PRIMERO (respeta foreign keys)
-- =====================================================

-- 1. Eliminar transacciones financieras (dependen de settlements y orders)
DELETE FROM public.account_transactions;

-- 2. Eliminar settlements (dependen de accounts)
DELETE FROM public.settlements;

-- 3. Eliminar order_status_updates (dependen de orders)
DELETE FROM public.order_status_updates;

-- 4. Eliminar reviews (dependen de orders)
DELETE FROM public.reviews;

-- 5. Eliminar payments (dependen de orders)
DELETE FROM public.payments;

-- 6. Eliminar order_items (dependen de orders y products)
DELETE FROM public.order_items;

-- 7. Eliminar orders (dependen de users y restaurants)
DELETE FROM public.orders;

-- 8. Eliminar products (dependen de restaurants)
DELETE FROM public.products;

-- 9. Eliminar accounts (dependen de users)
DELETE FROM public.accounts;

-- 10. Eliminar restaurants (dependen de users)
DELETE FROM public.restaurants;

-- 11. Eliminar users (tabla base, no depende de otras en public)
-- IMPORTANTE: Solo eliminamos de public.users, NO de auth.users
DELETE FROM public.users;

-- 12. Resetear secuencias si existen
-- Para order_status_updates que usa bigserial
ALTER SEQUENCE IF EXISTS order_status_updates_id_seq RESTART WITH 1;

-- =====================================================
-- VERIFICACIÓN FINAL
-- =====================================================
SELECT 
  'account_transactions' as tabla, COUNT(*) as registros FROM public.account_transactions
UNION ALL
SELECT 'settlements', COUNT(*) FROM public.settlements
UNION ALL
SELECT 'order_status_updates', COUNT(*) FROM public.order_status_updates
UNION ALL
SELECT 'reviews', COUNT(*) FROM public.reviews
UNION ALL
SELECT 'payments', COUNT(*) FROM public.payments
UNION ALL
SELECT 'order_items', COUNT(*) FROM public.order_items
UNION ALL
SELECT 'orders', COUNT(*) FROM public.orders
UNION ALL
SELECT 'products', COUNT(*) FROM public.products
UNION ALL
SELECT 'accounts', COUNT(*) FROM public.accounts
UNION ALL
SELECT 'restaurants', COUNT(*) FROM public.restaurants
UNION ALL
SELECT 'users', COUNT(*) FROM public.users;

-- ✅ Todas las tablas deberían mostrar 0 registros
-- ✅ Base de datos limpia lista para migración
