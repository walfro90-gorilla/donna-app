# CLAUDE.md - Doa Repartos

## Project Overview

Doa Repartos (`doa_repartos`) is a **Flutter food delivery platform** connecting clients, restaurants, delivery agents, and administrators. It targets Android, iOS, and Web (deployed via Vercel).

## Tech Stack

- **Framework:** Flutter (Dart SDK ^3.6.0)
- **Backend:** Supabase (PostgreSQL, Auth, Realtime, Storage, RPC functions)
- **Secondary:** Firebase Core 4.1.1 (analytics/cloud services)
- **Payments:** MercadoPago (custom integration)
- **Maps:** Google Maps Flutter + Flutter Map + Geolocator
- **Styling:** Material Design 3 with Google Fonts (Inter)
- **Deployment:** Vercel (web), native builds (Android/iOS)

## Project Structure

```
lib/
├── main.dart                     # Entry point, service initialization, routing
├── theme.dart                    # Material3 theme (light/dark), colors, typography
├── firebase_options.dart         # Firebase config (auto-generated)
├── core/                         # Core domain logic & infrastructure
│   ├── services/                 # Role-based business logic
│   │   ├── base_service.dart     # Base class for all services
│   │   ├── client_service.dart   # Client-facing logic
│   │   ├── delivery_service.dart # Delivery agent logic
│   │   ├── restaurant_service.dart
│   │   ├── admin_service.dart    # Admin panel logic
│   │   └── financial_service.dart
│   ├── session/                  # Centralized session management
│   │   ├── session_manager.dart  # Singleton session manager
│   │   └── user_session.dart     # Session data model
│   ├── registry/                 # Service locator pattern
│   │   └── service_registry.dart # Centralized service factory
│   ├── supabase/                 # Database abstraction
│   │   ├── rpc_names.dart        # RPC function name constants
│   │   └── supabase_rpc.dart     # RPC helper functions
│   ├── events/                   # Pub/sub event bus
│   │   └── event_bus.dart
│   ├── theme/
│   │   └── app_theme_controller.dart
│   └── utils/                    # Helpers (order status, addresses)
├── models/
│   └── doa_models.dart           # All data models in a single file
├── services/                     # Infrastructure & platform services
│   ├── realtime_service.dart     # Supabase real-time subscriptions
│   ├── polling_service.dart      # Fallback polling
│   ├── network_service.dart      # Connectivity monitoring
│   ├── navigation_service.dart   # Navigation management
│   ├── alert_sound_service.dart  # Audio notifications
│   ├── location_tracking_service.dart
│   ├── live_location_service.dart
│   ├── storage_service.dart      # File uploads
│   ├── mercadopago_service.dart  # Payment processing
│   ├── review_service.dart
│   ├── validation_service.dart
│   ├── places_service.dart       # Google Places API
│   ├── google_maps_loader*.dart  # Platform-specific Maps setup
│   └── mock_service.dart
├── supabase/
│   └── supabase_config.dart      # Supabase init & auth handling
├── screens/                      # UI screens organized by feature
│   ├── splash/                   # Splash/loading
│   ├── auth/                     # Login, register, email verification
│   ├── home/                     # Main dashboard
│   ├── restaurants/              # Restaurant browsing
│   ├── restaurant/               # Individual restaurant details
│   ├── orders/                   # Order management
│   ├── delivery/                 # Delivery agent dashboard (9 screens)
│   ├── profile/                  # User profile
│   ├── checkout/                 # Checkout flow
│   ├── reviews/                  # Review submission
│   ├── admin/                    # Admin panel (15+ screens)
│   └── public/                   # Public registration, privacy policy
└── widgets/                      # Reusable UI components
    ├── active_order_tracker*.dart
    ├── address_picker_modal.dart
    ├── live_delivery_map.dart
    ├── restaurant_card.dart
    ├── star_rating.dart
    └── ...
```

### Other Top-Level Directories

- `supabase/` - Supabase project configuration
- `supabase_scripts/` - Database migration and management scripts
- `sql_migrations/` - SQL database migrations
- `docs/` - Documentation (deployment checklist, feature plans, integration guides)
- `assets/` - Images, icons, audio files
- `android/`, `ios/`, `web/` - Platform-specific native configurations
- `CUARENTENA/` - Archived/quarantined code

## Build & Run Commands

```bash
# Install dependencies
flutter pub get

# Run on connected device/emulator (debug)
flutter run

# Run on web (debug)
flutter run -d chrome

# Analyze code for lint issues
flutter analyze

# Build for release (web)
flutter build web --release

# Build for release (Android)
flutter build apk --release

# Build for release (iOS)
flutter build ios --release

# Generate launcher icons
flutter pub run flutter_launcher_icons
```

## Architecture & Patterns

### State Management

No external state management library is used. The app relies on:

1. **SessionManager** (singleton) - Centralized user session, emits session change streams
2. **EventBus** (singleton) - Pub/sub inter-service communication via `AppEvent` subclasses
3. **ServiceRegistry** - Service locator/factory that activates role-specific services
4. **StreamControllers** - Reactive data flow within services; UI subscribes to streams
5. **StatefulWidget** - Local widget state with `setState()`

**Data flow:** Supabase Auth -> SessionManager -> ServiceRegistry activates role services -> Services emit data streams -> UI rebuilds from streams

### Key Design Patterns

- **Singleton:** SessionManager, EventBus, ServiceRegistry
- **Factory:** ServiceFactory for role-specific service creation
- **Observer:** EventBus for decoupled event-driven communication
- **Service Locator:** ServiceRegistry for dependency resolution
- **Repository:** Supabase as data repository via RPC calls

### Role System (RBAC)

Four user roles: `client`, `restaurant`, `delivery`, `admin`

- Services activate/deactivate based on the authenticated user's role
- Routes are gated by `SessionManager.currentSession.role`
- Supabase Row-Level Security (RLS) enforces data access at the database level

### Authentication

- Supabase Auth (email/password)
- Email verification required
- Session persistence via Supabase client
- Auth state changes trigger `SessionManager` updates which cascade to services

### Public Routes (no auth required)

`/`, `/login`, `/register`, `/email-verification`, `/nueva-donna`, `/nuevo-repartidor`, `/delivery/onboarding`, `/politica-de-privacidad`

## Data Models

All models live in `lib/models/doa_models.dart`. Key models:

- `DoaUser` - User profiles with role-specific fields
- `DoaRestaurant` - Restaurant info, menu, operating hours
- `DoaOrder` - Order details, status, items
- `DoaOrderItem` - Line items with product references
- `DoaProduct` - Menu items, pricing, combos
- `DoaDeliveryAgent` - Agent profiles, vehicle info
- `DoaTransaction` - Payment/financial records

Key enums: `UserRole`, `UserStatus` (online/offline/busy), `OrderStatus` (pending -> confirmed -> preparing -> ready -> on_the_way -> delivered | cancelled | not_delivered)

## Database & API

- **Supabase PostgreSQL** with Row-Level Security
- **RPC functions** for complex operations (see `core/supabase/rpc_names.dart` for the full list):
  - `create_order_safe`, `accept_order`, `update_user_location`
  - `register_delivery_agent_atomic`, `register_restaurant_atomic`
  - `find_nearby_restaurants`, `has_active_couriers`
- **Realtime channels** for live order/courier/restaurant updates
- **Direct table access** for CRUD on: orders, order_items, users, restaurants, products, transactions

## Theming & Styling

- **Material Design 3** with custom `ColorScheme`
- **Primary color:** `#E4007C` (Mexican Pink)
- **Font:** Google Inter
- **Dark mode:** Full support via `AppThemeController.themeMode` (ValueNotifier), persisted in SharedPreferences
- **Card border radius:** 16px, elevation: 2
- **AppBar:** No elevation, centered titles

## Code Conventions

### Naming

- **Classes:** `{Feature}Service`, `{Feature}Screen`, `Doa{Entity}` (models), `{Action}Event`
- **Methods:** camelCase; private with `_` prefix; booleans: `is{Property}`; async: `_load{Resource}`, `_fetch{Resource}`
- **Files:** snake_case (`session_manager.dart`, `home_screen.dart`)

### Import Order

```dart
// 1. Dart/Flutter SDK
import 'package:flutter/material.dart';
// 2. External packages
import 'package:supabase_flutter/supabase_flutter.dart';
// 3. Project imports (package:doa_repartos/...)
import 'package:doa_repartos/core/session/session_manager.dart';
```

### Logging

Uses `debugPrint` with emoji prefixes and module tags:

```dart
debugPrint('🚀 [MODULE] Starting action');
debugPrint('✅ [MODULE] Success');
debugPrint('❌ [MODULE] Error: $e');
debugPrint('⚠️ [MODULE] Warning');
debugPrint('🔄 [MODULE] Processing...');
```

### Language

- Code identifiers are in English
- Comments and debug messages mix Spanish and English (Spanish is predominant in user-facing strings and many comments)

### Error Handling

- Try-catch blocks around async operations with descriptive `debugPrint` logging
- Graceful fallbacks (e.g., polling service as fallback for realtime)
- User-facing error messages in Spanish via SnackBars

### File Organization

- One feature directory per screen category under `screens/`
- One service per file under `services/` and `core/services/`
- All data models consolidated in `models/doa_models.dart`
- Reusable components in `widgets/`
- Core infrastructure (session, events, registry, supabase helpers) in `core/`

## Deployment

### Web (Vercel)

- Config: `vercel.json` + `vercel_build.sh`
- Build: `flutter build web --release`
- Output: `build/web`
- SPA routing: all non-asset routes redirect to `index.html`

### Mobile

- Android: native config in `android/`
- iOS: native config in `ios/`

### Pre-deployment

See `docs/DEPLOYMENT_CHECKLIST.md` for verification steps.

## Configuration

- **Supabase:** URL and anon key in `lib/supabase/supabase_config.dart`
- **Firebase:** Project config in `lib/firebase_options.dart`
- **No `.env` files** - configuration is embedded in Dart source
- **Local storage:** SharedPreferences for theme preference and session data

## Testing

- No automated test suite is currently in place
- `flutter_test` SDK dependency is declared but no test files exist
- `mock_service.dart` provides mock data structures for development
- Testing is manual across Android, iOS, and web

## Documentation

Additional docs in `docs/`:

- `DEPLOYMENT_CHECKLIST.md` - Pre-deployment steps
- `MASTER_PLAN_REFACTOR_2025.md` - Refactoring roadmap
- `MERCADOPAGO_SETUP.md` - Payment integration guide
- `PAYMENT_TRANSACTIONS_FLOW.md` - Financial transaction workflows
- `TRACKER_REPAIR_PLAN.md` - Order tracking fixes
- `admin_panel_plan.md` - Admin dashboard architecture
- `driver_location_tracking_plan.md` - Real-time tracking plan
