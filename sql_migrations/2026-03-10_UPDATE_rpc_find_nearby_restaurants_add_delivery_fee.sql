-- Actualiza rpc_find_nearby_restaurants para incluir delivery_fee y renombrar delivery_time_min → delivery_time.
-- Requiere que la columna delivery_fee ya exista en la tabla restaurants.
-- Ver: sql_migrations/2026-03-10_ADD_restaurant_delivery_fee.sql

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
    cover_image_url text,
    rating numeric,
    delivery_time int,
    delivery_fee double precision,
    distance_meters double precision,
    is_open boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_location geography;
BEGIN
    user_location := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography;

    RETURN QUERY
    SELECT
        r.id,
        r.name,
        r.description,
        r.logo_url,
        r.cover_image_url,
        r.average_rating AS rating,
        r.estimated_delivery_time_minutes AS delivery_time,
        r.delivery_fee,
        ST_Distance(r.location, user_location) AS distance_meters,
        r.online AS is_open
    FROM public.restaurants r
    WHERE
        ST_DWithin(r.location, user_location, p_radius_meters)
        AND r.status = 'approved'
        AND (p_search_text IS NULL OR r.name ILIKE '%' || p_search_text || '%')
    ORDER BY
        r.online DESC,
        distance_meters ASC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

COMMENT ON FUNCTION public.rpc_find_nearby_restaurants IS
'Encuentra restaurantes en un radio (metros) usando PostGIS. Retorna distancia calculada, costo de envío y ordena por relevancia.';
