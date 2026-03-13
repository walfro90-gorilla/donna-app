-- ============================================================
-- Migration: Restaurant Business Hours Auto-Schedule
-- Date: 2026-03-13
-- Description: Adds business_hours_enabled + timezone columns,
--   and creates a pg_cron function that auto-toggles restaurants.online
--   every 5 minutes based on their weekly schedule.
--
-- PREREQUISITE: Enable pg_cron extension in Supabase Dashboard
--   → Database → Extensions → pg_cron
--
-- FREE TIER NOTE: pg_cron requires Pro plan. On Free tier, omit the
--   DO block at the end and run the cron job via Edge Function instead.
-- ============================================================

-- ── 1. New columns ──────────────────────────────────────────
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS business_hours_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS timezone text NOT NULL DEFAULT 'America/Mexico_City';

-- Partial index: only scan rows the cron actually evaluates
CREATE INDEX IF NOT EXISTS idx_restaurants_bh_enabled
  ON public.restaurants(business_hours_enabled)
  WHERE business_hours_enabled = true;

-- ── 2. business_hours JSON contract ─────────────────────────
-- The existing jsonb column must conform to this shape:
-- {
--   "monday":    { "enabled": true,  "open": "09:00", "close": "21:00" },
--   "tuesday":   { "enabled": true,  "open": "09:00", "close": "21:00" },
--   "wednesday": { "enabled": true,  "open": "09:00", "close": "21:00" },
--   "thursday":  { "enabled": true,  "open": "09:00", "close": "21:00" },
--   "friday":    { "enabled": true,  "open": "09:00", "close": "22:00" },
--   "saturday":  { "enabled": true,  "open": "10:00", "close": "22:00" },
--   "sunday":    { "enabled": false, "open": "10:00", "close": "18:00" }
-- }
-- Keys: lowercase English day names. Times: 24-hour "HH:MM" strings.
-- enabled:false = closed all day regardless of times.
-- NULL business_hours = no schedule → cron skips even if business_hours_enabled=true.

-- ── 3. Auto-toggle function ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.evaluate_restaurant_schedules()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r                RECORD;
  day_key          TEXT;
  day_data         JSONB;
  now_local        TIME;
  should_be_online BOOLEAN;
BEGIN
  -- Only process restaurants that opted into auto-scheduling
  FOR r IN
    SELECT id, business_hours, timezone, online
    FROM public.restaurants
    WHERE business_hours_enabled = true
      AND business_hours IS NOT NULL
      AND status = 'approved'
  LOOP
    -- to_char pads 'Day' with trailing spaces → trim is required
    day_key  := trim(lower(to_char(now() AT TIME ZONE r.timezone, 'Day')));
    day_data := r.business_hours -> day_key;

    IF day_data IS NULL OR NOT coalesce((day_data->>'enabled')::boolean, false) THEN
      -- No entry for this day or day marked disabled → closed
      should_be_online := false;
    ELSE
      now_local        := (now() AT TIME ZONE r.timezone)::time;
      should_be_online := now_local >= (day_data->>'open')::time
                       AND now_local <  (day_data->>'close')::time;
    END IF;

    -- Only write if state actually needs to change (avoids unnecessary updates)
    IF r.online IS DISTINCT FROM should_be_online THEN
      UPDATE public.restaurants
      SET    online     = should_be_online,
             updated_at = now()
      WHERE  id = r.id;
    END IF;
  END LOOP;
END;
$$;

-- Restrict execution: only postgres (cron) can call this, not API clients
GRANT EXECUTE ON FUNCTION public.evaluate_restaurant_schedules() TO postgres;
REVOKE EXECUTE ON FUNCTION public.evaluate_restaurant_schedules() FROM authenticated, anon;

-- ── 4. Register cron job (idempotent) ───────────────────────
-- Requires pg_cron extension to be enabled first.
-- Runs every 5 minutes → max 5-min lag between schedule and actual toggle.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'evaluate_restaurant_schedules'
  ) THEN
    PERFORM cron.schedule(
      'evaluate_restaurant_schedules',
      '*/5 * * * *',
      'SELECT public.evaluate_restaurant_schedules();'
    );
  END IF;
END;
$$;

-- ── 5. Verify ───────────────────────────────────────────────
-- After running, confirm with:
--   SELECT * FROM cron.job WHERE jobname = 'evaluate_restaurant_schedules';
--   SELECT public.evaluate_restaurant_schedules(); -- should affect 0 rows initially
