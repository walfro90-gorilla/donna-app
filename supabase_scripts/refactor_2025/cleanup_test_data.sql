-- =====================================================
-- LIMPIEZA DE DATOS DE TEST
-- =====================================================
-- Ejecutar este script después de completar los tests
-- para eliminar todos los datos de prueba
-- =====================================================

-- Eliminar usuarios de test (cascadeará a todas las tablas relacionadas)
DELETE FROM auth.users WHERE email IN (
  'test_client_refactor@example.com',
  'test_restaurant_refactor@example.com',
  'test_delivery_refactor@example.com',
  'otro_email@example.com',
  'test_short_pass@example.com',
  'email_invalido'
);

-- Verificar que se eliminaron correctamente
SELECT 
  'Limpieza completada' AS status,
  (SELECT COUNT(*) FROM users WHERE email LIKE '%refactor@example.com' OR email LIKE '%test%@example.com') AS usuarios_restantes;

-- ✅ usuarios_restantes debe ser 0
