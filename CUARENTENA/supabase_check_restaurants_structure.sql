-- Verificar estructura actual de la tabla restaurants
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
AND table_name = 'restaurants'
ORDER BY ordinal_position;

-- Verificar si existe la columna delivery_fee
SELECT EXISTS (
  SELECT 1 
  FROM information_schema.columns 
  WHERE table_schema = 'public' 
  AND table_name = 'restaurants' 
  AND column_name = 'delivery_fee'
) as delivery_fee_exists;