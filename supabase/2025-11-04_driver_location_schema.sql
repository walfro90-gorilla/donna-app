-- Schema for DoorDash-grade live location tracking
-- Safe to run multiple times (IF NOT EXISTS guards)

-- Optional: enable PostGIS if desired (requires extension privileges)
-- CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;

CREATE TABLE IF NOT EXISTS public.courier_locations_latest (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  order_id uuid NULL REFERENCES public.orders(id) ON DELETE SET NULL,
  lat double precision NOT NULL,
  lon double precision NOT NULL,
  accuracy double precision NULL,
  speed double precision NULL,
  heading double precision NULL,
  source text NULL,
  last_seen_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.courier_locations_history (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  order_id uuid NULL REFERENCES public.orders(id) ON DELETE SET NULL,
  lat double precision NOT NULL,
  lon double precision NOT NULL,
  accuracy double precision NULL,
  speed double precision NULL,
  heading double precision NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_courier_latest_user ON public.courier_locations_latest(user_id);
CREATE INDEX IF NOT EXISTS idx_courier_latest_order ON public.courier_locations_latest(order_id);

CREATE INDEX IF NOT EXISTS idx_courier_hist_user_time ON public.courier_locations_history(user_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_courier_hist_order_time ON public.courier_locations_history(order_id, recorded_at DESC);

-- If PostGIS is enabled, you can add a computed geometry and GIST index
-- ALTER TABLE public.courier_locations_latest ADD COLUMN IF NOT EXISTS geom geometry(Point, 4326);
-- ALTER TABLE public.courier_locations_history ADD COLUMN IF NOT EXISTS geom geometry(Point, 4326);
-- CREATE INDEX IF NOT EXISTS idx_courier_latest_geom ON public.courier_locations_latest USING GIST (geom);
-- CREATE INDEX IF NOT EXISTS idx_courier_hist_geom ON public.courier_locations_history USING GIST (geom);

-- RLS will be added in the policies file
ALTER TABLE public.courier_locations_latest ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courier_locations_history ENABLE ROW LEVEL SECURITY;
