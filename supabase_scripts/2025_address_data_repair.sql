-- =====================================================
-- 2025 ADDRESS DATA REPAIR SCRIPT
-- =====================================================
-- Purpose: Clean and repair inconsistent address data
-- Author: System
-- Date: 2025
--
-- This script:
-- 1. Identifies and fixes malformed address_structured entries
-- 2. Handles null/empty coordinates
-- 3. Repairs inconsistencies between legacy and structured data
-- 4. Provides data quality reports
-- =====================================================

BEGIN;

-- =====================================================
-- STEP 1: Create temporary audit table
-- =====================================================

CREATE TEMP TABLE address_repair_audit (
  user_id UUID,
  repair_type TEXT,
  old_value JSONB,
  new_value JSONB,
  repaired_at TIMESTAMP DEFAULT NOW()
);

-- =====================================================
-- STEP 2: Fix empty or malformed JSONB objects
-- =====================================================

-- Fix completely empty JSONB objects
WITH users_to_fix AS (
  SELECT id, address, lat, lon
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
-- STEP 3: Fix missing formatted_address field
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
-- STEP 4: Fix missing lat/lon in address_structured
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
-- STEP 5: Sync legacy columns with address_structured
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
-- STEP 6: Fix invalid coordinate ranges
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
-- STEP 7: Handle users with no address data at all
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
-- STEP 8: Remove duplicate/redundant fields
-- =====================================================

-- Clean up any unexpected fields in address_structured
-- (Keep only: formatted_address, lat, lon, street, city, state, country, postal_code, place_id)
UPDATE public.users
SET address_structured = (
  SELECT jsonb_object_agg(key, value)
  FROM jsonb_each(address_structured)
  WHERE key IN (
    'formatted_address', 'lat', 'lon', 'street', 'city', 
    'state', 'country', 'postal_code', 'place_id'
  )
)
WHERE address_structured IS NOT NULL;

COMMIT;

-- =====================================================
-- DATA QUALITY REPORT
-- =====================================================

-- Report: Total repairs made by type
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'ADDRESS DATA REPAIR SUMMARY';
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
END $$;

-- =====================================================
-- MANUAL VERIFICATION QUERIES
-- =====================================================

-- View repair audit log
-- SELECT * FROM address_repair_audit ORDER BY repaired_at DESC;

-- Check for remaining issues
-- SELECT 
--   id,
--   email,
--   address,
--   lat,
--   lon,
--   address_structured
-- FROM public.users
-- WHERE address_structured IS NULL
--    OR address_structured->>'formatted_address' IS NULL
--    OR (address_structured->>'lat' IS NULL AND lat IS NOT NULL)
-- LIMIT 20;

-- Verify data consistency
-- SELECT 
--   COUNT(*) as total,
--   COUNT(CASE WHEN address_structured IS NOT NULL THEN 1 END) as with_structured,
--   COUNT(CASE WHEN address_structured->>'lat' IS NOT NULL AND address_structured->>'lon' IS NOT NULL THEN 1 END) as with_coords,
--   COUNT(CASE WHEN lat = (address_structured->>'lat')::double precision THEN 1 END) as legacy_synced
-- FROM public.users;

-- Sample of repaired data
-- SELECT 
--   email,
--   address_structured->>'formatted_address' as formatted_address,
--   (address_structured->>'lat')::double precision as latitude,
--   (address_structured->>'lon')::double precision as longitude
-- FROM public.users
-- WHERE address_structured IS NOT NULL
-- LIMIT 10;
