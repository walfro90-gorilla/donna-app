# 📚 Master Documentation: Functions, Triggers & RPCs
> **Source of Truth** for Doña Repartos Database Logic.
> Last Updated: 2025-12-16

This document tracks all stored procedures, database triggers, and RLS policies to ensuring standard naming conventions and security best practices.

## 🏗️ Naming Conventions
- **RPCs (Callable from Flutter):** Must start with `rpc_` (e.g., `rpc_find_nearby_restaurants`).
- **Triggers:** Must start with `tr_` (e.g., `tr_on_auth_user_created`).
- **Trigger Functions:** Must start with `handle_` (e.g., `handle_new_user`).
- **indexes:** `idx_<table_name>_<column_name>` or `idx_<table_name>_gist` for spatial.

---

## 🚀 1. Remote Procedure Calls (RPCs)
Functions exposed to the Supabase Client (Flutter).

| Function Name | Parameters | Returns | Security | Description |
| :--- | :--- | :--- | :--- | :--- |
| `rpc_find_nearby_restaurants` | `lat` (float), `lon` (float), `radius` (int), `limit` (int), `offset` (int), `search` (text) | `Table (Restaurant Data)` | `DEFINER` | **Spatial Search.** Returns restaurants within radius, sorted by open status and distance. Uses GIST index. |
| `rpc_get_user_profile` | `user_id` (uuid) | `JSON` | `DEFINER` | Fetches full user profile including role-specific data (Client/Restaurant/Courier). |
| `rpc_create_user_profile` | `role` (text), `metadata` (json) | `void` | `DEFINER` | safely creates entries in `public.users` and role-specific tables (`client_profiles`, etc.). |
| `rpc_update_order_status` | `order_id` (uuid), `new_status` (text) | `void` | `DEFINER` | Updates order status and logs the event in `order_logs`. Handles business logic triggers. |

*(Add other RPCs here as they are audited/migrated)*

---

## ⚡ 2. Database Triggers
Automated logic that runs on table events.

| Trigger Name | Table | Event | Function | Description |
| :--- | :--- | :--- | :--- | :--- |
| `tr_on_auth_user_created` | `auth.users` | `INSERT` | `handle_new_user` | Creates initial entry in `public.users` when a user signs up. |
| `tr_updated_at` | *(All Tables)* | `BEFORE UPDATE` | `handle_updated_at` | Auto-updates `updated_at` timestamp. |
| `tr_audit_order_changes` | `orders` | `AFTER UPDATE` | `handle_order_audit` | Logs status changes to `order_logs`. |

---

## 🌍 3. Spatial & PostGIS
Configuration for geospatial features.

- **Extension:** `postgis` (Enabled in `extensions` schema).
- **SRID:** `4326` (WGS 84 - Standard GPS).
- **Column Type:** `GEOGRAPHY(Point, 4326)`.
- **Tables with Location:**
    - `restaurants`
    - `client_profiles` (Delivery capability)
    - `courier_locations_latest` (Real-time tracking)

---

## 🛡️ 4. Security Policies (RLS)
Brief overview of critical RLS policies.

- **Public Read:** Most catalogs (`products`, `restaurants`) are public read.
- **Owner Write:** Users can only edit their own profile/data (`auth.uid() = id`).
- **Admin Override:** `users.role = 'admin'` bypasses most checks via policies or `DEFINER` functions.

---

## 🧹 Maintenance Scripts
Located in `/supabase_scripts/`

1. `00_apply_documentation.sql`: Apply SQL comments to tables/columns.
2. `01_enable_postgis_and_migrate_locations.sql`: Enable PostGIS & migrate lat/lon to geography.
3. `02_standardize_language_no_spanglish.sql`: Fix 'cliente' -> 'client' data & constraints.
4. `03_optimized_spatial_rpc.sql`: The `rpc_find_nearby_restaurants` implementation.