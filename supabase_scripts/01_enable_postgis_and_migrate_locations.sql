-- ============================================================================
-- 📍 PHASE 2: POSTGIS MIGRATION (GEOSPATIAL EVOLUTION)
-- ============================================================================
-- Objetivo: Habilitar motor espacial profesional (DoorDash level)
-- y migrar datos legados (lat/lon) a tipos de datos geográficos nativos.
-- ============================================================================

-- 1. Habilitar extensión PostGIS (Requiere permisos de superusuario en Supabase)
CREATE EXTENSION IF NOT EXISTS postgis SCHEMA extensions;

-- 2. Agregar columnas geográficas a tablas clave
-- Usamos GEOGRAPHY(Point, 4326) que es el estándar GPS mundial (WGS 84)

-- A) Restaurantes
ALTER TABLE public.restaurants 
ADD COLUMN IF NOT EXISTS location GEOGRAPHY(Point, 4326);

-- B) Perfiles de Clientes (Para dirección de entrega default)
ALTER TABLE public.client_profiles 
ADD COLUMN IF NOT EXISTS location GEOGRAPHY(Point, 4326);

-- C) Historial de Repartidores (Ya son muchos datos, importante optimizar)
ALTER TABLE public.courier_locations_latest 
ADD COLUMN IF NOT EXISTS location GEOGRAPHY(Point, 4326);


-- 3. MIGRACIÓN DE DATOS (Backfill)
-- Convertir lat/lon existentes a puntos geográficos
-- Nota: ST_SetSRID(ST_MakePoint(lon, lat), 4326) crea el punto.

-- Restaurantes
UPDATE public.restaurants
SET location = ST_SetSRID(ST_MakePoint(location_lon::numeric, location_lat::numeric), 4326)::geography
WHERE location_lat IS NOT NULL AND location_lon IS NOT NULL;

-- Clientes
UPDATE public.client_profiles
SET location = ST_SetSRID(ST_MakePoint(lon::numeric, lat::numeric), 4326)::geography
WHERE lat IS NOT NULL AND lon IS NOT NULL;

-- Courier Latest
UPDATE public.courier_locations_latest
SET location = ST_SetSRID(ST_MakePoint(lon::numeric, lat::numeric), 4326)::geography
WHERE lat IS NOT NULL AND lon IS NOT NULL;


-- 4. CREAR ÍNDICES ESPACIALES (GIST)
-- Esto es lo que hace que las búsquedas "cerca de mí" sean O(log n) en lugar de O(n)
CREATE INDEX IF NOT EXISTS idx_restaurants_location ON public.restaurants USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_client_profiles_location ON public.client_profiles USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_courier_latest_location ON public.courier_locations_latest USING GIST (location);

-- 5. COMENTARIOS DE DOCUMENTACIÓN
COMMENT ON COLUMN public.restaurants.location IS 'PostGIS Geography Point. Source of Truth para búsquedas "Cerca de Mí".';
COMMENT ON COLUMN public.client_profiles.location IS 'PostGIS Geography Point. Ubicación default del cliente.';

-- ============================================================================
-- VERIFICACIÓN
-- Ejecuta esto después para probar:
-- SELECT name, ST_Distance(location, ST_MakePoint(-99.1332, 19.4326)::geography) as dist_metros
-- FROM public.restaurants
-- ORDER BY location <-> ST_MakePoint(-99.1332, 19.4326)::geography
-- LIMIT 5;
-- ============================================================================
