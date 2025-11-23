Title: Address and Client Profile Alignment Plan (.dm)

Context
- Backend schema updated to centralize client address and geolocation in public.client_profiles.
- auth.users remains for authentication; public.users holds app-level identity/role; client_profiles owns address, lat, lon, and optional address_structured.

Objectives
1) Read path: When fetching a client, always include client_profiles and read address/lat/lon from there.
2) Write path: Persist default delivery address to client_profiles (not public.users).
3) Backward compatibility: UI continues working with legacy data during transition.
4) Opt-in RPC: Provide SECURITY DEFINER RPC to update client address safely; fallback to direct upsert if RPC not deployed.

Deliverables in this commit
- Dart
  • DoaUser.fromJson now prefers json.client_profiles for address, lat, lon, address_structured.
  • DoaRepartosService.getUserById selects '*, client_profiles(*)'.
  • Orders queries join users with client_profiles for richer nested payloads.
  • New DoaRepartosService.updateClientDefaultAddress(...) uses RPC update_client_default_address if present; falls back to direct upsert into client_profiles.
  • CheckoutScreen loads address from client_profiles and saves via updateClientDefaultAddress (no more updates to public.users for address fields).

- SQL
  • supabase_scripts/2025-11-05_rpc_update_client_default_address.sql adds RPC: update_client_default_address(p_user_id, p_address, p_lat, p_lon, p_address_structured jsonb default null).

Rollout Steps
1) Database
   a. Review RLS on public.client_profiles: ensure authenticated users can select their own row; restrict updates to self.
   b. Run supabase_scripts/2025-11-05_rpc_update_client_default_address.sql.
   c. Verify: select from client_profiles where user_id = auth.uid(); update via RPC from SQL editor to confirm permissions.

2) App
   a. Deploy the code changes.
   b. Verify profile load: Profile and Checkout should show the saved address if it exists in client_profiles.
   c. Save flow: In Checkout, pick an address; confirm that client_profiles row updates with address, lat, lon, and (optional) address_structured.
   d. Order creation: Confirm orders continue to use delivery_* fields on orders; no dependency on users table for delivery location.

3) Backwards Compatibility
   • If a user lacks a client_profiles row or it has no lat/lon, DoaUser.fromJson falls back to legacy users.lat/lon/address.
   • During migration, both pathways function so the UI remains robust.

4) Future Enhancements (optional)
   • Introduce a view users_with_profiles exposing a flattened projection for simpler selects.
   • Add unique index on client_profiles (user_id) if not present.
   • Consolidate all address editing UIs to a single reusable component that writes to client_profiles.

Test Checklist
- getUserById returns users row with nested client_profiles for a known user.
- Checkout loads address/coordinates from client_profiles; saving updates that table.
- New RPC callable from app; if absent, fallback path works under RLS.
- Order flow unaffected; mini-map continues using order.delivery_lat/order.delivery_lon.
