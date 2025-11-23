-- Idempotent migration: add optional fields used by "Mi Restaurante" UI
-- Guided by existing app models (DoaRestaurant) and UI requirements

DO $$ BEGIN
  -- Facade image URL (publicly accessible URL from Supabase Storage)
  ALTER TABLE public.restaurants
    ADD COLUMN IF NOT EXISTS facade_image_url text;

  -- Basic geo-location fields (no PostGIS required)
  ALTER TABLE public.restaurants
    ADD COLUMN IF NOT EXISTS location_lat double precision,
    ADD COLUMN IF NOT EXISTS location_lon double precision,
    ADD COLUMN IF NOT EXISTS location_place_id text,
    ADD COLUMN IF NOT EXISTS address_structured jsonb;

  -- Ensure status column exists for approval workflow (nullable -> treated as pending in app)
  ALTER TABLE public.restaurants
    ADD COLUMN IF NOT EXISTS status text;

  -- Ensure updated_at exists since the app updates it on profile changes
  ALTER TABLE public.restaurants
    ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

EXCEPTION WHEN others THEN
  RAISE NOTICE 'Migration step skipped or already applied: %', SQLERRM;
END $$;

-- Optional: simple check on coordinates (not enforced if null)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE c.conname = 'chk_restaurants_location_valid'
      AND n.nspname = 'public'
      AND t.relname = 'restaurants'
  ) THEN
    ALTER TABLE public.restaurants
      ADD CONSTRAINT chk_restaurants_location_valid
      CHECK (
        (location_lat IS NULL AND location_lon IS NULL)
        OR (
          location_lat BETWEEN -90 AND 90 AND
          location_lon BETWEEN -180 AND 180
        )
      );
  END IF;
END $$;
