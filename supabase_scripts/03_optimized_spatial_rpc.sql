-- ============================================================================
-- 🚀 PHASE 2: RPC OPTIMIZATION (THE CROWN JEWEL)
-- ============================================================================
-- Objetivo: Crear función de búsqueda espacial que use el índice GIST.
-- Equivalente a lo que usa DoorDash para "Restaurantes cerca de mi".
-- ============================================================================

-- Eliminar versión vieja si existe (para evitar conflictos de argumentos)
DROP FUNCTION IF EXISTS public.rpc_find_nearby_restaurants;

CREATE OR REPLACE FUNCTION public.rpc_find_nearby_restaurants(
    p_lat double precision,
    p_lon double precision,
    p_radius_meters integer DEFAULT 5000,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0,
    p_search_text text DEFAULT NULL
)
RETURNS TABLE (
    id uuid,
    name text,
    description text,
    logo_url text,
    cover_image_url text, -- Agregado para UI cards
    rating numeric,
    delivery_time_min int,
    distance_meters double precision,
    is_open boolean
)
LANGUAGE plpgsql
SECURITY DEFINER -- Ejecutar con permisos de sistema (Bypasses RLS complejos si necesario, pero mantenemos filtros)
AS $$
DECLARE
    user_location geography;
BEGIN
    -- Convertir input (lat/lon) a Geografía para comparar con la DB
    user_location := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography;

    RETURN QUERY
    SELECT 
        r.id,
        r.name,
        r.description,
        r.logo_url,
        r.cover_image_url,
        r.average_rating as rating,
        r.estimated_delivery_time_minutes as delivery_time_min,
        -- Calcular distancia exacta usando PostGIS (Muy rápido gracias al índice)
        ST_Distance(r.location, user_location) as distance_meters,
        r.online as is_open
    FROM public.restaurants r
    WHERE 
        -- Filtro Espacial 1: "ST_DWithin" usa el índice GIST (Velocidad Óptima)
        ST_DWithin(r.location, user_location, p_radius_meters)
        
        -- Filtro Estado: Solo aprobados (opcional: y online)
        AND r.status = 'approved'
        
        -- Filtro Texto (Opcional)
        AND (p_search_text IS NULL OR r.name ILIKE '%' || p_search_text || '%')
    ORDER BY 
        r.online DESC, -- Abiertos primero
        distance_meters ASC -- Más cercanos después
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- DOCUMENTACIÓN
COMMENT ON FUNCTION public.rpc_find_nearby_restaurants IS 
'Power-Search: Encuentra restaurantes en un radio (metros) usando PostGIS. Retorna distancia calculada y ordena por relevancia.';
