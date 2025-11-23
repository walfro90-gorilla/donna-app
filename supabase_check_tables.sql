-- ====================================================================
-- VERIFICAR ESTRUCTURA DE TABLAS EN SUPABASE
-- ====================================================================

-- Verificar qué tablas existen actualmente
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;

-- Verificar si existen triggers problemáticos
SELECT 
  trigger_name,
  event_object_table,
  action_statement
FROM information_schema.triggers 
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- Verificar funciones que podrían estar causando problemas
SELECT 
  routine_name,
  routine_type,
  data_type
FROM information_schema.routines 
WHERE routine_schema = 'public'
AND routine_name LIKE '%trigger%' OR routine_name LIKE '%financial%'
ORDER BY routine_name;