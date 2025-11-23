-- Migración: Agregar campos de ubicación a tabla users
-- Fecha: 2025-01-XX
-- Descripción: Agrega lat, lon, y address_structured para todos los usuarios

-- 1. Agregar campos de ubicación a users
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION CHECK (lat IS NULL OR (lat >= -90 AND lat <= 90)),
  ADD COLUMN IF NOT EXISTS lon DOUBLE PRECISION CHECK (lon IS NULL OR (lon >= -180 AND lon <= 180)),
  ADD COLUMN IF NOT EXISTS address_structured JSONB;

-- 2. Comentarios descriptivos
COMMENT ON COLUMN public.users.lat IS 'Latitud de la ubicación del usuario (-90 a 90)';
COMMENT ON COLUMN public.users.lon IS 'Longitud de la ubicación del usuario (-180 a 180)';
COMMENT ON COLUMN public.users.address_structured IS 'Dirección estructurada en formato JSON de Google Maps';

-- 3. Índices para mejorar performance en búsquedas geoespaciales
CREATE INDEX IF NOT EXISTS idx_users_location ON public.users(lat, lon) WHERE lat IS NOT NULL AND lon IS NOT NULL;

-- 4. Migración de datos existentes: copiar location_* de restaurants a users para role='restaurante'
UPDATE public.users u
SET 
  lat = r.location_lat,
  lon = r.location_lon,
  address_structured = r.address_structured
FROM public.restaurants r
WHERE u.id = r.user_id
  AND u.role IN ('restaurante', 'restaurant')
  AND r.location_lat IS NOT NULL
  AND r.location_lon IS NOT NULL
  AND u.lat IS NULL; -- Solo migrar si aún no tiene ubicación

-- 5. Log de resultados
DO $$
DECLARE
  migrated_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO migrated_count
  FROM public.users
  WHERE lat IS NOT NULL;
  
  RAISE NOTICE 'Migración completada: % usuarios con ubicación', migrated_count;
END $$;
