# BLUEPRINT COMPLETO — Doa Repartos

> Generado: 2026-02-25

---

## 1. RESUMEN EJECUTIVO

Plataforma de delivery de comida multi-rol construida en Flutter + Supabase. Conecta **clientes**, **restaurantes**, **repartidores** y **administradores** en un solo app desplegado en Web (Vercel), Android e iOS.

---

## 2. TECH STACK

| Capa | Tecnología |
|---|---|
| Framework | Flutter (Dart SDK ^3.6.0) |
| Backend/DB | Supabase (PostgreSQL + RLS + Auth + Realtime + Storage) |
| Auth | Supabase Auth (email/password + OAuth) |
| Pagos | MercadoPago (custom integration) |
| Mapas | Google Maps Flutter + Flutter Map + Geolocator |
| Analytics | Firebase Core 4.1.1 |
| Tipografía | Google Fonts (Inter) |
| Diseño | Material Design 3 |
| Deploy | Vercel (web), APK/IPA (móvil) |
| Local storage | SharedPreferences |
| Audio | audioplayers 6.0.0 |
| Charts | fl_chart 0.68.0 |
| WebView | webview_flutter 4.0.0 |
| SVG | flutter_svg 2.0.0 |
| Archivos | file_picker |

---

## 3. ARQUITECTURA GENERAL

```
App Start
  └── main.dart
        ├── AppThemeController.initialize()  (SharedPreferences)
        ├── SupabaseConfig.initialize()
        ├── NetworkService.initialize()
        └── SessionManager.initialize()
              └── onAuthStateChanged()
                    └── _loadUserSession(user)
                          ├── Fetch public.users
                          ├── Load role-specific data
                          ├── _startSession(session)
                          │     ├── ServiceRegistry activa servicios
                          │     ├── AlertSoundService.setCurrentRole()
                          │     └── PollingService.initialize()
                          └── EventBus.publish(SessionStartedEvent)

UI Layer → SplashScreen → [role-based routing]
```

### Patrones de diseño usados

| Patrón | Implementación |
|---|---|
| Singleton | SessionManager, EventBus, ServiceRegistry, NetworkService, AlertSoundService |
| Factory | ServiceFactory (ClientServiceFactory, etc.) |
| Observer/Pub-Sub | EventBus con AppEvent subclasses |
| Service Locator | ServiceRegistry |
| Repository | Supabase como fuente de datos vía RPC |
| Stream-based reactivity | StreamControllers en cada Service |
| StatefulWidget | Estado local de UI |

---

## 4. SISTEMA DE ROLES (RBAC)

```
UserRole (enum)
├── client          → Clientes que ordenan comida
├── restaurant      → Dueños/operadores de restaurante
├── delivery_agent  → Repartidores
└── admin           → Administradores del sistema
```

**UserStatus:** `online` | `offline` | `busy`

**OrderStatus (flujo):**
```
pending → confirmed → in_preparation → ready_for_pickup → assigned → on_the_way → delivered
                                                                               ↘ cancelled
                                                                               ↘ not_delivered
```

**DeliveryAccountState:** `pending` | `approved`

---

## 5. MODELOS DE DATOS

Todos en `lib/models/doa_models.dart`

| Modelo | Tabla Supabase | Descripción |
|---|---|---|
| `DoaUser` | `users` | Perfil completo del usuario (todos los roles) |
| `DoaRestaurant` | `restaurants` | Info del restaurante, menú, horarios |
| `DoaOrder` | `orders` | Pedido con estado, items, agente |
| `DoaOrderItem` | `order_items` | Item de un pedido |
| `DoaProduct` | `products` | Producto del menú (con combos) |
| `DoaDeliveryAgent` | `delivery_agent_profiles` | Perfil del repartidor |
| `DoaTransaction` | `transactions` | Registros financieros |
| `DoaAccount` | `accounts` | Cuenta financiera por usuario |

### DoaUser — Campos clave

```dart
id, email, name, phone, address, role, status, isActive,
lat, lon, addressStructured,
profileImageUrl, idDocumentFrontUrl, idDocumentBackUrl,
vehicleType, vehiclePlate, vehicleModel, vehicleColor,
vehicleRegistrationUrl, vehicleInsuranceUrl, vehiclePhotoUrl,
emergencyContactName, emergencyContactPhone,
accountState (pending | approved),
emailConfirm
```

---

## 6. CORE INFRASTRUCTURE

### `lib/core/session/session_manager.dart`
**Singleton central de sesión**

| Método | Descripción |
|---|---|
| `initialize()` | Escucha auth state changes de Supabase |
| `_loadUserSession(user)` | Carga perfil + datos de rol desde `public.users` |
| `_startSession(session)` | Activa servicios, AudioService, PollingService |
| `_endSession(reason)` | Limpia servicios, EventBus, resetea estado |
| `signOut()` | Cierra sesión en Supabase |
| `_ensureFinancialAccountIfMissing()` | Crea cuenta financiera si no existe |

Emite: `SessionStartedEvent`, `SessionEndedEvent`, `SessionChangedEvent`

---

### `lib/core/registry/service_registry.dart`
**Service Locator + Factory**

| Método | Descripción |
|---|---|
| `registerFactory<T>()` | Registra factory para tipo de servicio |
| `getService<T>()` | Obtiene/crea servicio cacheado por usuario |
| `clearUserServices(userId)` | Limpia servicios al cerrar sesión |
| `clearAll()` | Limpia todos los servicios |

Factories registradas: `ClientServiceFactory`, `RestaurantServiceFactory`, `DeliveryServiceFactory`, `AdminServiceFactory`, `FinancialServiceFactory`

---

### `lib/core/events/event_bus.dart`
**Pub/Sub centralizado**

| Evento | Descripción |
|---|---|
| `SessionStartedEvent` | Sesión iniciada |
| `SessionEndedEvent` | Sesión cerrada |
| `SessionChangedEvent` | Cambio de usuario/rol |
| `OrderStatusChangedEvent` | Estado de orden actualizado |
| `OrderReadyEvent` | Orden lista para recoger |
| `ServiceActivatedEvent` | Servicio de rol activado |
| `ServiceDeactivatedEvent` | Servicio de rol desactivado |
| `DataUpdatedEvent` | Datos actualizados en un servicio |
| `ErrorEvent` | Error en cualquier servicio |

---

### `lib/core/supabase/rpc_names.dart`
**Constantes de RPC Functions**

| Constante | Función Supabase |
|---|---|
| `createOrderSafe` | `create_order_safe` |
| `acceptOrder` | `accept_order` |
| `registerDeliveryAgentAtomic` | `register_delivery_agent_atomic` |
| `registerRestaurantAtomic` | `register_restaurant_atomic` |
| `findNearbyRestaurants` | `rpc_find_nearby_restaurants` |
| `ensureClientProfileAndAccount` | `ensure_client_profile_and_account` |
| `ensureFinancialAccount` | `ensure_financial_account` |
| `updateUserLocation` | `update_user_location` |
| `updateClientDefaultAddress` | `update_client_default_address` |
| `upsertComboAtomic` | `upsert_combo_atomic` |
| `markOrderNotDelivered` | `mark_order_not_delivered` |
| `adminDeleteUser` | `rpc_admin_delete_user` |
| `hasActiveCouriers` | `has_active_couriers` |
| `getClientTotalDebt` | `get_client_total_debt` |

---

## 7. SERVICIOS DE NEGOCIO (ROLE-BASED)

### ClientService — `lib/core/services/client_service.dart`
**Rol:** `client`

| Método | Descripción | Tabla/RPC |
|---|---|---|
| `loadRestaurants()` | Carga restaurantes activos | `restaurants` |
| `searchRestaurants(lat, lon, query)` | Búsqueda geolocalizada por radio | `rpc_find_nearby_restaurants` |
| `loadUserOrders()` | Historial de pedidos (limit 20) | `orders` + joins |
| `checkActiveOrder()` | Verifica pedido en curso | `orders` |
| `createOrder()` | Crea nuevo pedido | `orders` |
| `cancelOrder(orderId)` | Cancela pedido | `OrderStatusHelper` |

**Streams:** `restaurantsStream`, `ordersStream`, `activeOrderStream`
**Auto-refresh:** cada 30 segundos

---

### RestaurantService — `lib/core/services/restaurant_service.dart`
**Rol:** `restaurant`

| Método | Descripción | Tabla/RPC |
|---|---|---|
| `startListening()` | Inicia realtime subscriptions | `orders`, `products` |
| `stopListening()` | Detiene subscriptions | — |
| `_loadRestaurantData()` | Carga datos del restaurante | `restaurants` |
| `_loadOrders()` | Órdenes del restaurante | `orders` + `order_items` |
| `_loadProducts()` | Productos del menú (activos) | `products` |
| `updateOrderStatus()` | Cambia estado de orden | `OrderStatusHelper` |
| `createProduct()` | Crea nuevo producto | `products` |

**Streams:** `dataStream`, `ordersStream`, `productsStream`
**Realtime:** subscripciones a `orders` y `products` vía Supabase Realtime

---

### DeliveryService — `lib/core/services/delivery_service.dart`
**Rol:** `delivery_agent`

| Método | Descripción | Tabla/RPC |
|---|---|---|
| `loadAvailableOrders()` | Pedidos listos para tomar | `orders` |
| `loadMyDeliveries()` | Mis entregas asignadas (limit 50) | `orders` |
| `checkActiveDelivery()` | Entrega en curso (`in_delivery`) | `orders` |
| `loadEarnings()` | Ganancias hoy/mes | `orders.delivery_fee` |
| `takeOrder(orderId)` | Toma un pedido (atómico) | `accept_order` RPC |
| `markAsDelivered(orderId)` | Marca entregado | `OrderStatusHelper` |

**Streams:** `availableOrdersStream`, `myDeliveriesStream`, `activeDeliveryStream`, `earningsStream`
**Auto-refresh:** cada 30 segundos

---

### AdminService — `lib/core/services/admin_service.dart`
**Rol:** `admin`

| Método | Descripción | Tabla/RPC |
|---|---|---|
| `loadUsers()` | Lista todos los usuarios | `user_profiles` |
| `loadRestaurants()` | Lista todos los restaurantes | `restaurants` |
| `loadOrders()` | Monitoreo de órdenes (limit 100) | `orders` |
| `loadDashboardStats()` | KPIs: usuarios, revenue, órdenes | Multi-table |
| `updateUserStatus()` | Activa/desactiva usuario | `user_profiles` |
| `updateRestaurantStatus()` | Aprueba/rechaza restaurante | `restaurants` |
| `cancelOrder(orderId, reason)` | Cancela orden con razón | `orders` |

**Streams:** `usersStream`, `restaurantsStream`, `ordersStream`, `dashboardStream`
**Auto-refresh:** cada 60 segundos

---

### FinancialService — `lib/core/services/financial_service.dart`
**Todos los roles con cuenta**

- Gestión de cuentas financieras (`accounts`)
- Historial de transacciones (`transactions`)
- Liquidaciones (`settlements`)

---

## 8. SERVICIOS DE INFRAESTRUCTURA

| Servicio | Archivo | Función |
|---|---|---|
| `RealtimeService` | `lib/services/realtime_service.dart` | Supabase Realtime channels para órdenes y ubicación |
| `PollingService` | `lib/services/polling_service.dart` | Fallback polling si falla realtime |
| `NetworkService` | `lib/services/network_service.dart` | Monitorea conectividad (connectivity_plus) |
| `AlertSoundService` | `lib/services/alert_sound_service.dart` | Audio notifications por rol |
| `LocationTrackingService` | `lib/services/location_tracking_service.dart` | Trackea ubicación del repartidor |
| `LiveLocationService` | `lib/services/live_location_service.dart` | Broadcast de ubicación en tiempo real |
| `StorageService` | `lib/services/storage_service.dart` | Uploads a Supabase Storage |
| `MercadoPagoService` | `lib/services/mercadopago_service.dart` | Integración de pagos |
| `PlacesService` | `lib/services/places_service.dart` | Google Places API para búsqueda de direcciones |
| `ReviewService` | `lib/services/review_service.dart` | Gestión de reseñas post-entrega |
| `ValidationService` | `lib/services/validation_service.dart` | Validación de formularios |
| `NavigationService` | `lib/services/navigation_service.dart` | Navegación programática |
| `OnboardingNotificationService` | `lib/services/onboarding_notification_service.dart` | Notificaciones de onboarding |
| `MockService` | `lib/services/mock_service.dart` | Datos mock para desarrollo |

---

## 9. PANTALLAS (SCREENS)

### PÚBLICAS (sin autenticación)

| Pantalla | Archivo | Ruta |
|---|---|---|
| Splash / Loader | `screens/splash/splash_screen.dart` | `/` |
| Login | `screens/auth/login_screen.dart` | `/login` |
| Registro Cliente | `screens/auth/register_screen.dart` | `/register` |
| Email Verification | `screens/auth/email_verification_screen.dart` | `/email-verification` |
| Cambiar Contraseña | `screens/auth/change_password_screen.dart` | — |
| Registro Restaurante | `screens/public/restaurant_registration_screen.dart` | `/nueva-donna` |
| Registro Repartidor | `screens/public/delivery_agent_registration_screen.dart` | `/nuevo-repartidor` |
| Signup Repartidor | `screens/public/delivery_signup_screen.dart` | — |
| Onboarding Repartidor | `screens/delivery/delivery_onboarding_dashboard.dart` | `/delivery/onboarding` |
| Política de Privacidad | `screens/public/privacy_policy_screen.dart` | `/politica-de-privacidad` |

---

### ROL: CLIENTE

| Pantalla | Archivo | Descripción |
|---|---|---|
| Home | `screens/home/home_screen.dart` | Dashboard: restaurantes, búsqueda, orden activa, onboarding |
| Restaurantes | `screens/restaurants/restaurants_screen.dart` | Listado con filtros |
| Detalle Restaurante | `screens/restaurants/restaurant_detail_screen.dart` | Menú, combos, agregar al carrito |
| Checkout | `screens/checkout/checkout_screen.dart` | Resumen, dirección, método de pago |
| Pago MercadoPago | `screens/checkout/mercadopago_checkout_screen.dart` | WebView con checkout MP |
| Formulario Tarjeta | `screens/checkout/card_payment_form_screen.dart` | Datos de tarjeta manual |
| Confirmación Orden | `screens/checkout/order_confirmation_screen.dart` | Orden creada con animación confeti |
| Mis Órdenes | `screens/orders/my_orders_screen.dart` | Historial de pedidos |
| Detalle Orden | `screens/orders/order_details_screen.dart` | Estado realtime + mapa repartidor |
| Perfil | `screens/profile/profile_screen.dart` | Editar datos, dirección, foto |
| Dejar Reseña | `screens/reviews/review_screen.dart` | Calificar restaurante y repartidor |

---

### ROL: RESTAURANTE

| Pantalla | Archivo | Descripción |
|---|---|---|
| Dashboard Principal | `screens/restaurant/restaurant_main_dashboard.dart` | Vista general con métricas |
| Dashboard Simple | `screens/restaurant/simple_orders_dashboard.dart` | Vista simplificada de órdenes |
| Gestión de Órdenes | `screens/restaurant/orders_management_screen.dart` | Lista + acciones (confirmar, preparar, listo) |
| Detalle Orden | `screens/restaurant/order_detail_restaurant_screen.dart` | Items + cambiar estado |
| Gestión de Productos | `screens/restaurant/products_management_screen.dart` | CRUD del menú |
| Editar Producto | `screens/restaurant/product_edit_screen.dart` | Precio, imagen, categoría |
| Editar Combo | `screens/restaurant/combo_edit_screen.dart` | Crear/editar combos (upsert_combo_atomic) |
| Perfil Restaurante | `screens/restaurant/restaurant_profile_screen.dart` | Vista pública del perfil |
| Editar Perfil | `screens/restaurant/restaurant_profile_edit_screen.dart` | Info, logo, horarios |
| Balance | `screens/restaurant/restaurant_balance_screen.dart` | Finanzas y transacciones |

---

### ROL: REPARTIDOR

| Pantalla | Archivo | Descripción |
|---|---|---|
| Dashboard Principal | `screens/delivery/delivery_main_dashboard.dart` | Online/offline, entrega activa, stats |
| Órdenes Disponibles | `screens/delivery/available_orders_screen.dart` | Pedidos listos para tomar |
| Órdenes Unificadas | `screens/delivery/unified_orders_screen.dart` | Disponibles + mis entregas (vista unificada) |
| Mis Entregas | `screens/delivery/my_deliveries_screen.dart` | Historial de entregas propias |
| Detalle Orden | `screens/delivery/delivery_order_detail_screen.dart` | Info, dirección, mapa, acciones |
| Ganancias | `screens/delivery/delivery_earnings_screen.dart` | Stats hoy/mes |
| Balance | `screens/delivery/delivery_balance_screen.dart` | Balance y transacciones |
| Liquidación | `screens/delivery/settlement_screen.dart` | Solicitar liquidación de saldo |

---

### ROL: ADMIN

| Pantalla | Archivo | Descripción |
|---|---|---|
| Dashboard Principal | `screens/admin/admin_main_dashboard.dart` | KPIs globales: usuarios, revenue, órdenes |
| Dashboard Simple | `screens/admin/simple_admin_dashboard.dart` | Vista simplificada |
| Monitor de Órdenes | `screens/admin/orders_monitor_screen.dart` | Monitoreo realtime de todas las órdenes |
| Gestión Restaurantes | `screens/admin/restaurants_management_screen.dart` | Lista y control |
| Detalle Restaurante | `screens/admin/restaurant_detail_admin_screen.dart` | Info + aprobar/desactivar |
| Gestión Clientes | `screens/admin/clients_management_screen.dart` | Lista de clientes |
| Detalle Cliente | `screens/admin/client_detail_admin_screen.dart` | Perfil, órdenes, deuda |
| Gestión Repartidores | `screens/admin/delivery_agents_management_screen.dart` | Lista de repartidores |
| Detalle Repartidor | `screens/admin/delivery_agent_detail_admin_screen.dart` | Perfil, aprobar cuenta, documentos |
| Gestión Usuarios | `screens/admin/users_management_screen.dart` | Todos los usuarios |
| Libro Contable | `screens/admin/admin_account_ledger_screen.dart` | Registro contable global |
| Liquidaciones | `screens/admin/settlements_management_screen.dart` | Gestionar liquidaciones |
| Liquidaciones Manuales | `screens/admin/manual_settlements_screen.dart` | Liquidaciones manuales |
| Balance Cero | `screens/admin/balance_zero_screen.dart` | Gestión de saldos en cero |
| Búsqueda Global | `screens/admin/admin_global_search.dart` | Buscar cualquier entidad |

---

## 10. WIDGETS REUTILIZABLES

| Widget | Archivo | Descripción |
|---|---|---|
| `ActiveOrderTracker` | `widgets/active_order_tracker.dart` | Banner de orden activa en tiempo real |
| `ActiveOrderTrackerV2` | `widgets/active_order_tracker_v2.dart` | Versión mejorada |
| `MultiOrderTracker` | `widgets/multi_order_tracker.dart` | Tracker para múltiples órdenes |
| `LiveDeliveryMap` | `widgets/live_delivery_map.dart` | Mapa con ubicación del repartidor |
| `RestaurantCard` | `widgets/restaurant_card.dart` | Card de restaurante en listados |
| `AddressPickerModal` | `widgets/address_picker_modal.dart` | Modal de selección de dirección con mapa |
| `AddressSearchField` | `widgets/address_search_field.dart` | Búsqueda de dirección (Google Places) |
| `ImageUploadField` | `widgets/image_upload_field.dart` | Upload de imágenes a Supabase Storage |
| `StarRating` | `widgets/star_rating.dart` | Calificación con estrellas |
| `AppLogo` | `widgets/app_logo.dart` | Logo de la app |
| `ProfileCompletionCard` | `widgets/profile_completion_card.dart` | Progreso del perfil |
| `DeliveryProfileProgressCard` | `widgets/delivery_profile_progress_card.dart` | Progreso del perfil de repartidor |
| `WelcomeOnboardingCard` | `widgets/welcome_onboarding_card.dart` | Card de bienvenida onboarding |
| `PhoneDialInput` | `widgets/phone_dial_input.dart` | Input de teléfono con código de país |

---

## 11. TABLAS SUPABASE

| Tabla | Descripción |
|---|---|
| `users` (public) | Perfiles de usuario — todos los roles |
| `user_profiles` | Vista/tabla extendida de perfiles |
| `user_preferences` | Preferencias del usuario (onboarding, etc.) |
| `client_profiles` | Perfil específico del cliente |
| `delivery_agent_profiles` | Perfil y documentos del repartidor |
| `restaurants` | Restaurantes registrados |
| `products` | Productos/menú de los restaurantes |
| `orders` | Pedidos |
| `order_items` | Items de un pedido |
| `accounts` | Cuentas financieras por usuario |
| `transactions` | Historial de transacciones |
| `settlements` | Liquidaciones |
| `reviews` | Reseñas de usuarios |

---

## 12. FLUJOS PRINCIPALES

### Flujo Cliente — Hacer un Pedido

```
Home
  └── RestaurantDetailScreen  →  Explorar menú, agregar al carrito
        └── CheckoutScreen  →  Confirmar dirección + método de pago
              ├── MercadoPagoCheckoutScreen  (WebView)
              └── create_order_safe RPC
                    └── OrderConfirmationScreen  (confeti)
                          └── ActiveOrderTracker en Home  (realtime)
                                └── OrderDetailsScreen  (mapa + estado)
                                      └── ReviewScreen  (post-entrega)
```

### Flujo Restaurante — Gestionar Orden

```
RestaurantMainDashboard  →  Nueva orden llega vía Realtime + AlertSound
  └── OrdersManagementScreen  →  Confirmar orden
        └── OrderDetailRestaurantScreen
              ├── "Confirmar"   → status: confirmed
              ├── "Preparando"  → status: in_preparation
              └── "Listo"       → status: ready_for_pickup
```

### Flujo Repartidor — Entregar un Pedido

```
DeliveryMainDashboard  →  Orden disponible aparece
  └── AvailableOrdersScreen  →  Ver detalle
        └── accept_order RPC  →  Asignación atómica
              └── DeliveryOrderDetailScreen
                    ├── Mapa con dirección del cliente
                    ├── "En camino"  → status: on_the_way
                    └── "Entregado"  → status: delivered  →  loadEarnings()
```

### Flujo Admin — Aprobación de Repartidor

```
DeliveryAgentsManagementScreen  →  Repartidor pendiente
  └── DeliveryAgentDetailAdminScreen
        ├── Ver documentos (foto, cédula, vehículo)
        └── Aprobar  →  accountState: approved
              └── Repartidor habilitado para operar
```

---

## 13. ROUTING

```dart
// RUTAS PÚBLICAS (no requieren autenticación)
'/'                         → SplashScreen (routing por rol)
'/login'                    → LoginScreen
'/register'                 → RegisterScreen
'/email-verification'       → EmailVerificationScreen
'/nueva-donna'              → RestaurantRegistrationScreen
'/nuevo-repartidor'         → DeliverySignupScreen
'/delivery/onboarding'      → DeliveryOnboardingDashboard
'/politica-de-privacidad'   → PrivacyPolicyScreen

// RUTAS PROTEGIDAS (pasan por SplashScreen)
'/home'                     → HomeScreen (dispatch por rol)

// Las demás pantallas se navegan via Navigator.push() directamente
```

---

## 14. THEMING

| Propiedad | Valor |
|---|---|
| Sistema | Material Design 3 |
| Color primario | `#E4007C` (Mexican Pink) |
| Font | Inter (Google Fonts) |
| Dark/Light mode | Soporte completo, persiste en SharedPreferences |
| Cards | border-radius 16px, elevation 2 |
| AppBar | Sin elevación, títulos centrados |
| Controller | `AppThemeController` (ValueNotifier<ThemeMode>) |

---

## 15. LOGGING CONVENTIONS

```dart
debugPrint('🚀 [MODULE] Starting action');
debugPrint('✅ [MODULE] Success');
debugPrint('❌ [MODULE] Error: $e');
debugPrint('⚠️ [MODULE] Warning');
debugPrint('🔄 [MODULE] Processing...');
```

---

## 16. ÁREAS DE MEJORA IDENTIFICADAS

| Area | Observación |
|---|---|
| Tests | No hay suite de pruebas automatizadas |
| State Management | Sin Provider/Riverpod — complejidad crece con la app |
| `restaurant_service.dart` vs `restaurant_service_simple.dart` | Duplicidad — dos implementaciones paralelas |
| `admin_main_dashboard.dart` vs `simple_admin_dashboard.dart` | Duplicidad similar |
| `active_order_tracker.dart` vs `v2` | Versiones paralelas sin deprecar la v1 |
| `OrderStatus` enums | Inconsistencia: `in_delivery` vs `on_the_way` en distintos lugares |
| `CUARENTENA/` | Código archivado que debería limpiarse |
| Firebase Core | Declarado en pubspec pero sin uso activo evidente |
| `_backup_restaurant_registration_v2_screen.dart` | Archivo de backup en producción — eliminar |
| Google Maps renderer | Inicializado en LEGACY mode para compatibilidad Android |

---

## 17. ESTRUCTURA DE ARCHIVOS COMPLETA

```
lib/
├── main.dart                                    # Entry point, routing, lifecycle
├── theme.dart                                   # Material3 light/dark themes
├── firebase_options.dart                        # Firebase config (auto-generated)
│
├── core/
│   ├── events/
│   │   └── event_bus.dart                       # Pub/Sub centralizado
│   ├── registry/
│   │   └── service_registry.dart               # Service Locator + Factories
│   ├── services/
│   │   ├── base_service.dart                   # Base class para servicios
│   │   ├── client_service.dart                 # Lógica de cliente
│   │   ├── delivery_service.dart               # Lógica de repartidor
│   │   ├── restaurant_service.dart             # Lógica de restaurante (con Realtime)
│   │   ├── restaurant_service_simple.dart      # Versión simplificada
│   │   ├── admin_service.dart                  # Lógica de admin
│   │   └── financial_service.dart             # Lógica financiera
│   ├── session/
│   │   ├── session_manager.dart               # Singleton de sesión
│   │   └── user_session.dart                  # Modelo de sesión
│   ├── supabase/
│   │   ├── rpc_names.dart                     # Constantes de RPCs
│   │   └── supabase_rpc.dart                  # Helpers de RPC
│   ├── theme/
│   │   └── app_theme_controller.dart          # ValueNotifier de ThemeMode
│   └── utils/
│       ├── address_helper.dart
│       └── order_status_helper.dart
│
├── models/
│   └── doa_models.dart                         # Todos los modelos de datos
│
├── services/
│   ├── alert_sound_service.dart
│   ├── google_maps_loader.dart
│   ├── google_maps_loader_stub.dart
│   ├── google_maps_loader_web.dart
│   ├── live_location_service.dart
│   ├── location_tracking_service.dart
│   ├── mercadopago_service.dart
│   ├── mock_service.dart
│   ├── navigation_service.dart
│   ├── network_service.dart
│   ├── onboarding_notification_service.dart
│   ├── places_service.dart
│   ├── polling_service.dart
│   ├── realtime_service.dart
│   ├── review_service.dart
│   ├── storage_service.dart
│   └── validation_service.dart
│
├── supabase/
│   └── supabase_config.dart
│
├── screens/
│   ├── admin/                                  # 15 pantallas de admin
│   ├── auth/                                   # Login, register, verificación
│   ├── checkout/                               # Checkout y pagos
│   ├── delivery/                               # 9 pantallas de repartidor
│   ├── home/                                   # Dashboard cliente
│   ├── orders/                                 # Órdenes del cliente
│   ├── profile/                               # Perfil de usuario
│   ├── public/                                # Registro público + privacidad
│   ├── restaurant/                            # 10 pantallas de restaurante
│   ├── restaurants/                           # Exploración de restaurantes
│   ├── reviews/                               # Reseñas
│   └── splash/                               # Splash + routing inicial
│
└── widgets/                                    # 14 widgets reutilizables
```
