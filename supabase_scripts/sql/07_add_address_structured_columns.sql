-- Script SQL para agregar las columnas JSONB de direcciones estructuradas
-- Ejecutar DESPUÉS de habilitar PostGIS y ajustar current_location

-- ==============================================================================
-- 1. Añadir columna JSONB para la dirección estructurada en orders
-- ==============================================================================
ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS delivery_address_structured JSONB;

COMMENT ON COLUMN public.orders.delivery_address_structured IS 
'Dirección de entrega estructurada (JSONB) devuelta por Google Address Validation API o Reverse Geocoding. Ejemplo: {"street_number":"123", "route":"Main St", "city":"Ciudad", "state":"Estado", "country":"País", "postal_code":"12345"}';

-- ==============================================================================
-- 2. Añadir columna JSONB para la dirección estructurada en restaurants
-- ==============================================================================
ALTER TABLE public.restaurants
ADD COLUMN IF NOT EXISTS address_structured JSONB;

COMMENT ON COLUMN public.restaurants.address_structured IS 
'Dirección del restaurante estructurada (JSONB) devuelta por Google Address Validation API o Reverse Geocoding. Permite búsquedas avanzadas y análisis por componentes de dirección.';

-- ==============================================================================
-- 3. (Opcional) Índice para búsquedas rápidas en campos JSONB
-- ==============================================================================
-- Si necesitas buscar por ciudad, estado, etc., puedes crear índices GIN:
-- CREATE INDEX IF NOT EXISTS idx_orders_delivery_address_structured ON public.orders USING GIN (delivery_address_structured);
-- CREATE INDEX IF NOT EXISTS idx_restaurants_address_structured ON public.restaurants USING GIN (address_structured);

-- ==============================================================================
-- 4. (Recomendado) Estandarizar el tipo de current_location a PostGIS GEOGRAPHY
-- ==============================================================================
-- Si la columna users.current_location no es de tipo PostGIS, ejecuta:
-- ALTER TABLE public.users
-- ALTER COLUMN current_location TYPE GEOGRAPHY(Point, 4326) USING NULL;

-- Nota: Si la columna ya tiene datos, necesitarás un USING clause más complejo
-- para convertir el tipo actual. Si está vacía o NULL, el comando de arriba funciona.

-- ==============================================================================
-- Fin del script
-- ==============================================================================
