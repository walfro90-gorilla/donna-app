-- Agregar campo pickup_code a la tabla orders
-- Este código de 4 dígitos será usado por el repartidor para recoger el pedido en el restaurante

-- Agregar la columna pickup_code
ALTER TABLE orders 
ADD COLUMN pickup_code VARCHAR(4);

-- Crear función para generar código de recogida de 4 dígitos
CREATE OR REPLACE FUNCTION generate_pickup_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
  -- Genera un número aleatorio entre 1000 y 9999 (4 dígitos)
  RETURN LPAD((1000 + FLOOR(RANDOM() * 9000))::TEXT, 4, '0');
END;
$$;

-- Crear función para asignar pickup_code automáticamente cuando se crea una orden
CREATE OR REPLACE FUNCTION assign_pickup_code()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Si no se especifica pickup_code, generar uno automáticamente
  IF NEW.pickup_code IS NULL THEN
    NEW.pickup_code := generate_pickup_code();
  END IF;
  
  RETURN NEW;
END;
$$;

-- Crear trigger para asignar pickup_code automáticamente en INSERT
DROP TRIGGER IF EXISTS trigger_assign_pickup_code ON orders;
CREATE TRIGGER trigger_assign_pickup_code
  BEFORE INSERT ON orders
  FOR EACH ROW
  EXECUTE FUNCTION assign_pickup_code();

-- Actualizar las órdenes existentes que no tienen pickup_code
UPDATE orders 
SET pickup_code = generate_pickup_code()
WHERE pickup_code IS NULL;

-- Comentarios para referencia
COMMENT ON COLUMN orders.pickup_code IS 'Código de 4 dígitos que el repartidor debe proporcionar al restaurante para recoger el pedido';
COMMENT ON FUNCTION generate_pickup_code() IS 'Genera un código aleatorio de 4 dígitos para recogida del pedido';
COMMENT ON FUNCTION assign_pickup_code() IS 'Asigna automáticamente un pickup_code cuando se crea una nueva orden';