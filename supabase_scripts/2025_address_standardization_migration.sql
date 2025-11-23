-- =====================================================
-- 2025 ADDRESS STANDARDIZATION MIGRATION
-- =====================================================
-- Purpose: Standardize address and geo-location storage across all tables
-- Author: System
-- Date: 2025
--
-- This migration:
-- 1. Adds address_structured JSONB column to 'users' table
-- 2. Migrates existing lat/lon columns to address_structured
-- 3. Ensures all address data follows consistent JSON structure
-- =====================================================

BEGIN;

-- =====================================================
-- STEP 1: Add address_structured column to users table
-- =====================================================

ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS address_structured JSONB;

COMMENT ON COLUMN public.users.address_structured IS 
'Structured address with geo-location: {
  "formatted_address": "string",
  "lat": number,
  "lon": number,
  "street": "string" (optional),
  "city": "string" (optional),
  "state": "string" (optional),
  "country": "string" (optional),
  "postal_code": "string" (optional),
  "place_id": "string" (optional)
}';

-- =====================================================
-- STEP 2: Migrate existing lat/lon data to address_structured
-- =====================================================

-- For users with lat/lon but no address_structured
UPDATE public.users
SET address_structured = jsonb_build_object(
  'formatted_address', COALESCE(address, 'Dirección no especificada'),
  'lat', lat,
  'lon', lon
)
WHERE lat IS NOT NULL 
  AND lon IS NOT NULL
  AND (address_structured IS NULL OR address_structured::text = '{}');

-- For users with only address but no coordinates
UPDATE public.users
SET address_structured = jsonb_build_object(
  'formatted_address', address,
  'lat', NULL,
  'lon', NULL
)
WHERE address IS NOT NULL 
  AND address != ''
  AND (lat IS NULL OR lon IS NULL)
  AND (address_structured IS NULL OR address_structured::text = '{}');

-- =====================================================
-- STEP 3: Add index for efficient geo queries
-- =====================================================

-- Create index on lat/lon within JSONB for geo-spatial queries
CREATE INDEX IF NOT EXISTS idx_users_address_structured_coords
ON public.users ((address_structured->>'lat'), (address_structured->>'lon'))
WHERE address_structured IS NOT NULL;

-- Create GIN index for full JSONB search
CREATE INDEX IF NOT EXISTS idx_users_address_structured_gin
ON public.users USING GIN (address_structured);

-- =====================================================
-- STEP 4: Add validation constraints
-- =====================================================

-- Ensure lat is between -90 and 90
ALTER TABLE public.users
ADD CONSTRAINT check_users_address_lat_range
CHECK (
  address_structured IS NULL OR
  (address_structured->>'lat')::numeric IS NULL OR
  ((address_structured->>'lat')::numeric BETWEEN -90 AND 90)
);

-- Ensure lon is between -180 and 180
ALTER TABLE public.users
ADD CONSTRAINT check_users_address_lon_range
CHECK (
  address_structured IS NULL OR
  (address_structured->>'lon')::numeric IS NULL OR
  ((address_structured->>'lon')::numeric BETWEEN -180 AND 180)
);

-- =====================================================
-- STEP 5: Create helper functions
-- =====================================================

-- Function to extract lat from address_structured
CREATE OR REPLACE FUNCTION public.get_user_lat(user_id UUID)
RETURNS DOUBLE PRECISION AS $$
  SELECT (address_structured->>'lat')::double precision
  FROM public.users
  WHERE id = user_id;
$$ LANGUAGE SQL STABLE;

-- Function to extract lon from address_structured
CREATE OR REPLACE FUNCTION public.get_user_lon(user_id UUID)
RETURNS DOUBLE PRECISION AS $$
  SELECT (address_structured->>'lon')::double precision
  FROM public.users
  WHERE id = user_id;
$$ LANGUAGE SQL STABLE;

-- Function to extract formatted address
CREATE OR REPLACE FUNCTION public.get_user_formatted_address(user_id UUID)
RETURNS TEXT AS $$
  SELECT address_structured->>'formatted_address'
  FROM public.users
  WHERE id = user_id;
$$ LANGUAGE SQL STABLE;

-- Function to calculate distance between two users (Haversine formula)
CREATE OR REPLACE FUNCTION public.calculate_distance_between_users(
  user_id_1 UUID,
  user_id_2 UUID
)
RETURNS DOUBLE PRECISION AS $$
DECLARE
  lat1 DOUBLE PRECISION;
  lon1 DOUBLE PRECISION;
  lat2 DOUBLE PRECISION;
  lon2 DOUBLE PRECISION;
  R CONSTANT DOUBLE PRECISION := 6371; -- Earth radius in kilometers
  dLat DOUBLE PRECISION;
  dLon DOUBLE PRECISION;
  a DOUBLE PRECISION;
  c DOUBLE PRECISION;
BEGIN
  -- Get coordinates for user 1
  SELECT (address_structured->>'lat')::double precision, 
         (address_structured->>'lon')::double precision
  INTO lat1, lon1
  FROM public.users WHERE id = user_id_1;

  -- Get coordinates for user 2
  SELECT (address_structured->>'lat')::double precision, 
         (address_structured->>'lon')::double precision
  INTO lat2, lon2
  FROM public.users WHERE id = user_id_2;

  -- Return NULL if any coordinate is missing
  IF lat1 IS NULL OR lon1 IS NULL OR lat2 IS NULL OR lon2 IS NULL THEN
    RETURN NULL;
  END IF;

  -- Haversine formula
  dLat := radians(lat2 - lat1);
  dLon := radians(lon2 - lon1);
  
  a := sin(dLat/2) * sin(dLat/2) +
       cos(radians(lat1)) * cos(radians(lat2)) *
       sin(dLon/2) * sin(dLon/2);
  
  c := 2 * atan2(sqrt(a), sqrt(1-a));
  
  RETURN R * c; -- Distance in kilometers
END;
$$ LANGUAGE plpgsql STABLE;

-- =====================================================
-- STEP 6: Create view for easy access to address data
-- =====================================================

CREATE OR REPLACE VIEW public.users_with_formatted_addresses AS
SELECT 
  id,
  email,
  name,
  phone,
  role,
  address AS legacy_address,
  lat AS legacy_lat,
  lon AS legacy_lon,
  address_structured,
  address_structured->>'formatted_address' AS formatted_address,
  (address_structured->>'lat')::double precision AS latitude,
  (address_structured->>'lon')::double precision AS longitude,
  address_structured->>'street' AS street,
  address_structured->>'city' AS city,
  address_structured->>'state' AS state,
  address_structured->>'country' AS country,
  address_structured->>'postal_code' AS postal_code,
  address_structured->>'place_id' AS place_id,
  created_at,
  updated_at
FROM public.users;

COMMENT ON VIEW public.users_with_formatted_addresses IS 
'Convenient view that extracts all address components from address_structured JSONB column';

-- =====================================================
-- STEP 7: Update RLS policies if needed
-- =====================================================

-- Ensure existing RLS policies cover address_structured
-- (No changes needed as column-level policies inherit table policies)

COMMIT;

-- =====================================================
-- VERIFICATION QUERIES (run manually after migration)
-- =====================================================

-- Check how many users have address_structured populated
-- SELECT 
--   COUNT(*) as total_users,
--   COUNT(address_structured) as with_structured_address,
--   COUNT(*) - COUNT(address_structured) as missing_structured_address
-- FROM public.users;

-- Check sample of migrated data
-- SELECT 
--   id, 
--   email,
--   address as old_address,
--   lat as old_lat,
--   lon as old_lon,
--   address_structured
-- FROM public.users
-- LIMIT 10;

-- Test distance calculation
-- SELECT 
--   u1.email as user1,
--   u2.email as user2,
--   public.calculate_distance_between_users(u1.id, u2.id) as distance_km
-- FROM public.users u1, public.users u2
-- WHERE u1.id != u2.id
--   AND u1.address_structured IS NOT NULL
--   AND u2.address_structured IS NOT NULL
-- LIMIT 5;
