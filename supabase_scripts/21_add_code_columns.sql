-- Agregar columnas de códigos si no existen
DO $$
BEGIN
    -- Agregar confirm_code si no existe
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'confirm_code'
    ) THEN
        ALTER TABLE orders ADD COLUMN confirm_code VARCHAR(3);
        RAISE NOTICE 'Columna confirm_code agregada';
    ELSE
        RAISE NOTICE 'Columna confirm_code ya existe';
    END IF;

    -- Agregar pickup_code si no existe
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'orders' AND column_name = 'pickup_code'
    ) THEN
        ALTER TABLE orders ADD COLUMN pickup_code VARCHAR(4);
        RAISE NOTICE 'Columna pickup_code agregada';
    ELSE
        RAISE NOTICE 'Columna pickup_code ya existe';
    END IF;
END $$;