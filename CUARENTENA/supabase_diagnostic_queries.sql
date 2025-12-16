-- ===================================================================
-- QUERIES DIAGNÓSTICOS PARA REVISAR CONSTRAINTS Y HACER BACKFILL
-- ===================================================================

-- 1️⃣ LISTAR TODAS LAS CONSTRAINTS EN LA TABLA 'orders'
-- ===================================================================
SELECT 
    tc.constraint_name,
    tc.constraint_type,
    tc.table_name,
    cc.column_name,
    tc.is_deferrable,
    tc.initially_deferred
FROM information_schema.table_constraints tc
JOIN information_schema.constraint_column_usage cc 
    ON tc.constraint_name = cc.constraint_name
WHERE tc.table_name = 'orders'
ORDER BY tc.constraint_type, tc.constraint_name;

-- 2️⃣ CONSTRAINTS CHECK ESPECÍFICAS (detectar las que afectan 'status')
-- ===================================================================
SELECT 
    conname as constraint_name,
    contype as constraint_type,
    conrelid::regclass as table_name,
    pg_get_constraintdef(oid) as constraint_definition
FROM pg_constraint 
WHERE conrelid = 'orders'::regclass
  AND contype = 'c'  -- CHECK constraints
ORDER BY conname;

-- 3️⃣ REVISAR VALORES ACTUALES DE 'status' EN LA TABLA
-- ===================================================================
SELECT 
    status,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
FROM orders 
GROUP BY status
ORDER BY count DESC;

-- 4️⃣ BACKFILL SIMULADO (ESTIMACIÓN SIN CAMBIOS)
-- ===================================================================
-- Mostrar cuántas filas serían afectadas por el backfill
SELECT 
    'SIMULATION: Rows that would be updated in backfill' as operation,
    COUNT(*) as affected_rows
FROM orders 
WHERE status NOT IN ('pending', 'confirmed', 'preparing', 'ready', 'assigned', 'picked_up', 'delivered', 'cancelled');

-- 5️⃣ VALORES "PROBLEMÁTICOS" QUE SERÍAN NORMALIZADOS
-- ===================================================================
SELECT 
    status as current_status,
    'pending' as would_become,
    COUNT(*) as affected_rows
FROM orders 
WHERE status NOT IN ('pending', 'confirmed', 'preparing', 'ready', 'assigned', 'picked_up', 'delivered', 'cancelled')
GROUP BY status
ORDER BY affected_rows DESC;

-- 6️⃣ VERIFICAR SI LA TABLA 'order_status_updates' YA EXISTE
-- ===================================================================
SELECT 
    table_name,
    table_type
FROM information_schema.tables 
WHERE table_name = 'order_status_updates'
  AND table_schema = 'public';

-- ===================================================================
-- INSTRUCCIONES DE USO:
-- ===================================================================
-- 1. Ejecuta estos queries UNO POR UNO en el SQL Editor de Supabase
-- 2. Revisa los resultados antes de proceder con cambios
-- 3. El query #4 te dirá exactamente cuántas filas serían afectadas
-- 4. El query #5 te mostrará qué valores "raros" existen (si los hay)
-- 5. Si todo se ve bien, procede con el script de implementación