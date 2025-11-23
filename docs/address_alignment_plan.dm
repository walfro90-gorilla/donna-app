Title: Client Address Alignment Plan (users ⇄ client_profiles)

Goal
- Ensure all user address and geolocation data is written to and read from public.client_profiles using the standardized address_structured JSON.
- Remove reliance on legacy columns (users.address, users.lat, users.lon) in the app.

Scope of changes
1) Read Path
   - Always fetch users with client_profiles join: select '*, client_profiles(*)'.
   - Models (DoaUser) already prefer client_profiles.address/address_structured/lat/lon and expose getters.

2) Write Path (Forms and Flows)
   - Registration (client and restaurant): keep basic user insert; persist address via update_client_default_address RPC.
   - Checkout/Home address pickers: write via DoaRepartosService.updateClientDefaultAddress (uses RPC or safe upsert fallback).
   - Delivery agent onboarding: continue using atomic RPC (register_delivery_agent_atomic); embedded address is compatible.

3) Backend RPCs (SQL)
   - ensure_client_profile_and_account(p_user_id uuid): idempotently creates client_profiles + accounts(user_id,'client').
   - update_client_default_address(p_user_id, p_address, p_lat, p_lon, p_address_structured): writes to client_profiles.
   - update_user_location(...): optional wrapper to call update_client_default_address(auth.uid(), ...).

Implementation steps
1. Code refactor
   - home_screen.dart
     • Load user via DoaRepartosService.getUserById (with client_profiles).
     • Persist address via DoaRepartosService.updateClientDefaultAddress.
     • Remove users.{address,lat,lon,address_structured} fallback updates.
   - supabase_config.dart
     • _createUserProfileImmediately: insert only identity fields (no address/lat/lon).
     • After insert, ensure client_profiles + account and set default address using updateClientDefaultAddress.

2. SQL
   - Add supabase/2025-11-client-address-rpcs.sql with the two SECURITY DEFINER functions.

3. QA checklist
   - New signup (email/password) + Google login: profile created; client_profiles row exists; address saved when provided.
   - Checkout: selecting address stores it; verify on client_profiles; mini-map uses order.delivery_lat/lon and restaurant.address_structured.
   - Home: address picker reads prefilled values from client_profiles, saves back correctly.
   - No writes to users.{address,lat,lon,address_structured} remain.

Rollout notes
- The RPC file is safe to run multiple times (create or replace).
- If RLS blocks direct upserts, the SECURITY DEFINER functions bypass RLS as intended.
