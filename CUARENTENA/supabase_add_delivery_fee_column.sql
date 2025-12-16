-- 🔧 SCRIPT PARA AGREGAR COLUMNA DELIVERY_FEE A RESTAURANTS

-- Verificar si la columna ya existe
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'restaurants' 
        AND column_name = 'delivery_fee'
    ) THEN
        -- Agregar la columna delivery_fee
        ALTER TABLE restaurants 
        ADD COLUMN delivery_fee DECIMAL(10,2) DEFAULT 3.00;
        
        RAISE NOTICE '✅ Columna delivery_fee agregada exitosamente';
    ELSE
        RAISE NOTICE '⚠️ La columna delivery_fee ya existe';
    END IF;
END $$;

-- Actualizar todos los restaurantes existentes con una tarifa por defecto
UPDATE restaurants 
SET delivery_fee = 3.00 
WHERE delivery_fee IS NULL;

-- Verificar resultado
SELECT 
    id, 
    name, 
    delivery_fee 
FROM restaurants 
LIMIT 5;

-- Mostrar confirmación
SELECT '✅ Script ejecutado exitosamente. Todos los restaurantes tienen delivery_fee configurado.' as resultado;