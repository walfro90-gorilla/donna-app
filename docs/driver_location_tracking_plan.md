# Master Plan: Real‑time Delivery Location Tracking (DoorDash‑grade)

Goal: Deliver reliable, privacy‑safe, real‑time tracking for delivery agents that scales, is RLS‑safe, and works with your current Flutter code (no code edits required to adopt the core path).

Summary of what we’ll do:
- Keep profile data in public.users, but stop treating it as the canonical live location. Use dedicated tables:
  - courier_locations_latest: one row per driver with their last known position (broadcast via Realtime, safe to poll).
  - courier_locations_history: breadcrumb trail for the last 24–72 hours for audits and dispute resolution.
- Provide two RPCs with SECURITY DEFINER:
  - update_my_location(...) — upserts into latest, throttles inserts into history, also mirrors lat/lon into users for backward‑compat.
  - get_driver_location_for_order(order_id) — server‑side authorized single record read for map pins.
- Harden RLS policies so only the driver, the client of an active order, the restaurant owner of that order, or admins can read the driver’s live coordinates.

Why not store live pings in users?
- High write rate: frequent updates cause contention and noisy updated_at; users is for profile/state, not high‑frequency telemetry.
- Real‑time: Realtime on a hot users table couples unrelated concerns; a dedicated table lets us index, prune, and scale cleanly.
- Privacy & retention: History has different retention needs from profile data. Separate makes retention and access controls simpler.

What this plan changes today
- Adds schema + RLS + RPCs (see SQL files in supabase/). The current app already calls update_my_location and optionally reads get_driver_location_for_order; after applying migrations, both paths will work. The fallback that reads users.lat/lon will continue to work because the RPC mirrors into users.

Data model (high‑level)
- courier_locations_latest
  - user_id (PK, uuid → public.users.id)
  - order_id (uuid → public.orders.id, nullable)
  - lat, lon (double precision)
  - accuracy, speed, heading (double precision, nullable)
  - last_seen_at (timestamptz)
- courier_locations_history
  - id (bigserial PK)
  - user_id (uuid)
  - order_id (uuid, nullable)
  - lat, lon, accuracy, speed, heading
  - recorded_at (timestamptz)

Authorization (RLS)
- Insert/Update latest: only the driver themselves (auth.uid() == user_id).
- Select latest: allowed when one of these is true:
  1) self (driver)
  2) client of an active order tied to this driver (orders.status IN active states)
  3) restaurant owner of that order (restaurants.user_id == auth.uid())
  4) admin (public.users.role = 'admin')
- History: write by driver (and via RPC). Read can mirror latest or be further restricted; by default we keep the same rules.

RPC behaviors
- update_my_location(lat, lng, accuracy?, speed?, heading?, order_id?)
  - If order_id not provided, resolves to the driver’s most recent active order server‑side.
  - Upserts into latest, mirrors to users.lat/lon for backward compatibility, and appends to history every ≥10 seconds or ≥~11m movement.
  - SECURITY DEFINER, validates auth.uid().
- get_driver_location_for_order(order_id)
  - SECURITY DEFINER, but manually authorizes caller (client of the order, driver of the order, restaurant owner, or admin). Returns a small tuple: lat, lng, updated_at, bearing, speed.

Realtime vs polling (how DoorDash‑like UIs behave)
- Latest table is optimized for supabase_realtime; subscribe by user_id (= delivery_agent_id from the order). Your current UI polls every ~8s; that remains fine. For snappier movement, switch to Realtime on courier_locations_latest.

Retention & performance
- Keep latest indefinitely (tiny table).
- History retention: schedule a nightly task to delete entries older than 72h/7d depending on policy. Create simple index strategy (by user_id, order_id, recorded_at). See SQL comments for suggested cron.

Verification checklist (now)
1) After applying SQL, in SQL editor:
   - select update_my_location(19.4326, -99.1332);
   - select * from courier_locations_latest where user_id = auth.uid();
   - select * from users where id = auth.uid(); -- lat/lon should mirror
2) With an active order assigned to the driver, run:
   - select * from get_driver_location_for_order('<order_id>');
   - From a client account tied to that order, the same query should work; from a random account, it should fail with not allowed.

Does the driver app send location on accept?
- Yes. In Flutter, upon accepting an order we call LocationTrackingService.instance.start(orderId: ...), which checks permission and then calls update_my_location every 30 seconds. On delivery detail screen, tracking starts for active statuses and stops when delivered.
- If you observe no pins moving:
  - Ensure update_my_location exists (this migration adds it) and returns 200.
  - Ensure the driver granted location permission. For background/locked‑screen reliability on physical devices, enable foreground service on Android and background modes on iOS (see “Mobile‑side hardening” below).

Mobile‑side hardening (when you’re ready)
- Throttle: 5–10s while navigating; 20–30s while idle.
- Android: foreground service notification + set update interval; iOS: allowsBackgroundLocationUpdates + significant change fallback.
- Send accuracy, heading, speed; only store in history when moved >10–15m or ≥10s elapsed.
- Stop updates when order is delivered/cancelled or driver goes offline.

Rollout steps
1) Apply supabase/2025-11-04_driver_location_schema.sql
2) Apply supabase/2025-11-04_driver_location_policies.sql
3) Apply supabase/2025-11-04_driver_location_functions.sql
4) Test with an assigned order. The existing Flutter code will start populating latest and users.lat/lon immediately.

Security notes
- All sensitive reads are protected by RLS and, for RPC, by explicit authorization checks.
- SECURITY DEFINER functions set search_path = public and never accept user_id as a parameter (we derive from auth.uid()).

Next optional improvements
- Switch client tracker to Realtime on courier_locations_latest instead of polling.
- Add PostGIS geometry with GIST index for proximity search (optional), and a nightly retention job for history.
