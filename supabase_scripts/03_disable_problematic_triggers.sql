-- ==========================================
-- PASO 3: Deshabilitar triggers problemáticos (OPCIONAL)
-- ==========================================

-- Solo ejecutar si tienes problemas con triggers existentes
-- Deshabilitar triggers que pueden estar causando conflictos

-- Verificar qué triggers existen
SELECT trigger_name, event_object_table, action_statement 
FROM information_schema.triggers 
WHERE event_object_table IN ('orders', 'order_items');

-- Si hay triggers problemáticos, deshabilitarlos temporalmente:
-- ALTER TABLE orders DISABLE TRIGGER ALL;
-- ALTER TABLE order_items DISABLE TRIGGER ALL;

-- NOTA: Solo descomenta las líneas de arriba si identificas triggers específicos
-- que están causando el error "trigger functions can only be called as triggers"