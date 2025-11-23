-- =====================================================
-- 2025 COMPLETE ADDRESS STANDARDIZATION & REPAIR
-- =====================================================
-- Purpose: Single unified script for address standardization and data repair
-- Author: System
-- Date: 2025
--
-- This script combines:
-- 1. Schema migration (add address_structured column)
-- 2. Data migration (populate address_structured from legacy columns)
-- 3. Data repair (fix inconsistencies and malformed data)
-- 4. Helper functions and views
-- =====================================================

BEGIN;

-- =====================================================
-- PART 1: SCHEMA MIGRATION
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
-- STEP 2: Initial migration from legacy columns
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
-- STEP 3: Add indexes for performance
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
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'check_users_address_lat_range'
  ) THEN
    ALTER TABLE public.users
    ADD CONSTRAINT check_users_address_lat_range
    CHECK (
      address_structured IS NULL OR
      (address_structured->>'lat')::numeric IS NULL OR
      ((address_structured->>'lat')::numeric BETWEEN -90 AND 90)
    );
  END IF;
END $$;

-- Ensure lon is between -180 and 180
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'check_users_address_lon_range'
  ) THEN
    ALTER TABLE public.users
    ADD CONSTRAINT check_users_address_lon_range
    CHECK (
      address_structured IS NULL OR
      (address_structured->>'lon')::numeric IS NULL OR
      ((address_structured->>'lon')::numeric BETWEEN -180 AND 180)
    );
  END IF;
END $$;

-- =====================================================
-- PART 2: DATA REPAIR
-- =====================================================

-- STEP 5: Create temporary audit table
-- =====================================================

CREATE TEMP TABLE address_repair_audit (
  user_id UUID,
  repair_type TEXT,
  old_value JSONB,
  new_value JSONB,
  repaired_at TIMESTAMP DEFAULT NOW()
);

-- =====================================================
-- STEP 6: Fix empty or malformed JSONB objects
-- =====================================================

-- Fix completely empty JSONB objects
WITH users_to_fix AS (
  SELECT id, address, lat, lon, address_structured
  FROM public.users
  WHERE address_structured IS NOT NULL 
    AND address_structured::text IN ('{}', 'null', '""', '')
)
INSERT INTO address_repair_audit (user_id, repair_type, old_value, new_value)
SELECT 
  id,
  'empty_jsonb_repair',
  address_structured,
  jsonb_build_object(
    'formatted_address', COALESCE(address, 'Dirección no especificada'),
    'lat', lat,
    'lon', lon
  )
FROM users_to_fix;

UPDATE public.users
SET address_structured = jsonb_build_object(
  'formatted_address', COALESCE(address, 'Dirección no especificada'),
  'lat', lat,
  'lon', lon
)
WHERE address_structured IS NOT NULL 
  AND address_structured::text IN ('{}', 'null', '""', '');

-- =====================================================
-- STEP 7: Fix missing formatted_address field
-- =====================================================

WITH users_to_fix AS (
  SELECT id, address, address_structured
  FROM public.users
  WHERE address_structured IS NOT NULL
    AND (
      address_structured->>'formatted_address' IS NULL OR
      address_structured->>'formatted_address' = ''
    )
    AND (address IS NOT NULL AND address != '')
)
INSERT INTO address_repair_audit (user_id, repair_type, old_value, new_value)
SELECT 
  id,
  'missing_formatted_address',
  address_structured,
  address_structured || jsonb_build_object('formatted_address', address)
FROM users_to_fix;

UPDATE public.users
SET address_structured = address_structured || jsonb_build_object('formatted_address', address)
WHERE address_structured IS NOT NULL
  AND (
    address_structured->>'formatted_address' IS NULL OR
    address_structured->>'formatted_address' = ''
  )
  AND (address IS NOT NULL AND address != '');

-- =====================================================
-- STEP 8: Fix missing lat/lon in address_structured
-- =====================================================

-- When lat/lon exist in legacy columns but not in address_structured
WITH users_to_fix AS (
  SELECT id, lat, lon, address_structured
  FROM public.users
  WHERE address_structured IS NOT NULL
    AND lat IS NOT NULL
    AND lon IS NOT NULL
    AND (
      (address_structured->>'lat')::text IS NULL OR
      (address_structured->>'lon')::text IS NULL OR
      (address_structured->>'lat')::text = 'null' OR
      (address_structured->>'lon')::text = 'null'
    )
)
INSERT INTO address_repair_audit (user_id, repair_type, old_value, new_value)
SELECT 
  id,
  'missing_coordinates_in_structured',
  address_structured,
  address_structured || jsonb_build_object('lat', lat, 'lon', lon)
FROM users_to_fix;

UPDATE public.users
SET address_structured = address_structured || jsonb_build_object('lat', lat, 'lon', lon)
WHERE address_structured IS NOT NULL
  AND lat IS NOT NULL
  AND lon IS NOT NULL
  AND (
    (address_structured->>'lat')::text IS NULL OR
    (address_structured->>'lon')::text IS NULL OR
    (address_structured->>'lat')::text = 'null' OR
    (address_structured->>'lon')::text = 'null'
  );

-- =====================================================
-- STEP 9: Sync legacy columns with address_structured
-- =====================================================

-- Update legacy lat/lon columns from address_structured (for consistency)
WITH users_to_sync AS (
  SELECT 
    id,
    (address_structured->>'lat')::double precision AS new_lat,
    (address_structured->>'lon')::double precision AS new_lon
  FROM public.users
  WHERE address_structured IS NOT NULL
    AND address_structured->>'lat' IS NOT NULL
    AND address_structured->>'lon' IS NOT NULL
    AND (
      lat IS NULL OR
      lon IS NULL OR
      lat != (address_structured->>'lat')::double precision OR
      lon != (address_structured->>'lon')::double precision
    )
)
INSERT INTO address_repair_audit (user_id, repair_type, old_value, new_value)
SELECT 
  u.id,
  'sync_legacy_columns',
  jsonb_build_object('lat', u.lat, 'lon', u.lon),
  jsonb_build_object('lat', s.new_lat, 'lon', s.new_lon)
FROM public.users u
JOIN users_to_sync s ON u.id = s.id;

UPDATE public.users u
SET 
  lat = (address_structured->>'lat')::double precision,
  lon = (address_structured->>'lon')::double precision
WHERE address_structured IS NOT NULL
  AND address_structured->>'lat' IS NOT NULL
  AND address_structured->>'lon' IS NOT NULL
  AND (
    lat IS NULL OR
    lon IS NULL OR
    lat != (address_structured->>'lat')::double precision OR
    lon != (address_structured->>'lon')::double precision
  );

-- =====================================================
-- STEP 10: Fix invalid coordinate ranges
-- =====================================================

-- Fix lat values outside valid range (-90 to 90)
WITH users_to_fix AS (
  SELECT id, address_structured
  FROM public.users
  WHERE address_structured IS NOT NULL
    AND address_structured->>'lat' IS NOT NULL
    AND (
      (address_structured->>'lat')::numeric < -90 OR
      (address_structured->>'lat')::numeric > 90
    )
)
INSERT INTO address_repair_audit (user_id, repair_type, old_value, new_value)
SELECT 
  id,
  'invalid_latitude',
  address_structured,
  address_structured || jsonb_build_object('lat', NULL)
FROM users_to_fix;

UPDATE public.users
SET address_structured = address_structured || jsonb_build_object('lat', NULL),
    lat = NULL
WHERE address_structured IS NOT NULL
  AND address_structured->>'lat' IS NOT NULL
  AND (
    (address_structured->>'lat')::numeric < -90 OR
    (address_structured->>'lat')::numeric > 90
  );

-- Fix lon values outside valid range (-180 to 180)
WITH users_to_fix AS (
  SELECT id, address_structured
  FROM public.users
  WHERE address_structured IS NOT NULL
    AND address_structured->>'lon' IS NOT NULL
    AND (
      (address_structured->>'lon')::numeric < -180 OR
      (address_structured->>'lon')::numeric > 180
    )
)
INSERT INTO address_repair_audit (user_id, repair_type, old_value, new_value)
SELECT 
  id,
  'invalid_longitude',
  address_structured,
  address_structured || jsonb_build_object('lon', NULL)
FROM users_to_fix;

UPDATE public.users
SET address_structured = address_structured || jsonb_build_object('lon', NULL),
    lon = NULL
WHERE address_structured IS NOT NULL
  AND address_structured->>'lon' IS NOT NULL
  AND (
    (address_structured->>'lon')::numeric < -180 OR
    (address_structured->>'lon')::numeric > 180
  );

-- =====================================================
-- STEP 11: Handle users with no address data at all
-- =====================================================

-- Set minimal structure for users with completely missing address data
WITH users_to_fix AS (
  SELECT id
  FROM public.users
  WHERE address_structured IS NULL
    AND (address IS NULL OR address = '')
    AND lat IS NULL
    AND lon IS NULL
)
INSERT INTO address_repair_audit (user_id, repair_type, old_value, new_value)
SELECT 
  id,
  'create_default_structure',
  NULL,
  jsonb_build_object('formatted_address', 'Dirección no especificada', 'lat', NULL, 'lon', NULL)
FROM users_to_fix;

UPDATE public.users
SET address_structured = jsonb_build_object(
  'formatted_address', 'Dirección no especificada',
  'lat', NULL,
  'lon', NULL
)
WHERE address_structured IS NULL
  AND (address IS NULL OR address = '')
  AND lat IS NULL
  AND lon IS NULL;

-- =====================================================
-- STEP 12: Clean redundant fields
-- =====================================================

-- Keep only standard fields in address_structured
UPDATE public.users
SET address_structured = (
  SELECT jsonb_object_agg(key, value)
  FROM jsonb_each(address_structured)
  WHERE key IN (
    'formatted_address', 'lat', 'lon', 'street', 'city', 
    'state', 'country', 'postal_code', 'place_id'
  )
)
WHERE address_structured IS NOT NULL
  AND address_structured != '{}'::jsonb;

-- =====================================================
-- PART 3: HELPER FUNCTIONS
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
-- STEP 13: Create view for easy access
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

COMMIT;

-- =====================================================
-- DATA QUALITY REPORT
-- =====================================================

DO $$
DECLARE
  rec RECORD;
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'ADDRESS MIGRATION & REPAIR COMPLETE';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  
  -- Total users
  RAISE NOTICE 'Total users: %', (SELECT COUNT(*) FROM public.users);
  
  -- Users with address_structured
  RAISE NOTICE 'Users with address_structured: %', 
    (SELECT COUNT(*) FROM public.users WHERE address_structured IS NOT NULL);
  
  -- Users with complete address data
  RAISE NOTICE 'Users with complete address (formatted + coords): %',
    (SELECT COUNT(*) FROM public.users 
     WHERE address_structured IS NOT NULL
       AND address_structured->>'formatted_address' IS NOT NULL
       AND address_structured->>'lat' IS NOT NULL
       AND address_structured->>'lon' IS NOT NULL);
  
  -- Users missing coordinates
  RAISE NOTICE 'Users missing coordinates: %',
    (SELECT COUNT(*) FROM public.users 
     WHERE address_structured IS NOT NULL
       AND (address_structured->>'lat' IS NULL OR address_structured->>'lon' IS NULL));
  
  -- Repairs made
  RAISE NOTICE '';
  RAISE NOTICE 'Repairs performed:';
  
  FOR rec IN (
    SELECT repair_type, COUNT(*) as count
    FROM address_repair_audit
    GROUP BY repair_type
    ORDER BY count DESC
  ) LOOP
    RAISE NOTICE '  - %: % users', rec.repair_type, rec.count;
  END LOOP;
  
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Migration successful!';
  RAISE NOTICE '========================================';
END $$;

-- =====================================================
-- VERIFICATION QUERIES (run manually if needed)
-- =====================================================

-- Check sample of migrated data:
-- SELECT id, email, name, address, lat, lon, address_structured 
-- FROM public.users 
-- LIMIT 10;

-- Test helper functions:
-- SELECT public.get_user_formatted_address(id) 
-- FROM public.users 
-- LIMIT 5;

-- View formatted addresses:
-- SELECT * FROM public.users_with_formatted_addresses LIMIT 10;
