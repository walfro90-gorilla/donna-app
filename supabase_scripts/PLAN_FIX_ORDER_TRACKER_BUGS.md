# 🔧 PLAN DE REPARACIÓN - Order Tracker Bugs

## 📋 **RESUMEN EJECUTIVO**

**Fecha:** 2025-01-XX  
**Estado:** ✅ DIAGNÓSTICO COMPLETADO - Listo para Reparación

---

## 🔍 **DIAGNÓSTICO - 3 PROBLEMAS IDENTIFICADOS**

### **PROBLEMA #1: Error al Abrir el Tracker** ❌

**Síntoma:**
```
Error abriendo el tracker: PostgrestException(message: {"code":"42703","details":null,"hint":null,"message":"column users_1.address does not exist"}, code: 400, details:, hint: null)
```

**Causa Raíz:**
Los queries en **`order_details_screen.dart`** y **`order_confirmation_screen.dart`** están haciendo JOIN con la tabla `users` e intentando obtener el campo `address`, que **YA NO EXISTE** tras el refactor 2025.

**Ubicaciones del Error:**
1. **`lib/screens/orders/order_details_screen.dart:99`**
   - Query: `user:user_id (id, name, role, email, phone, address, avatar_url, ...)`
   - **❌ `address` no existe en `users`**

2. **`lib/screens/checkout/order_confirmation_screen.dart:168`**
   - Query: `user:user_id (id, name, role, email, phone, address, avatar_url, ...)`
   - **❌ `address` no existe en `users`**

3. **`lib/screens/checkout/order_confirmation_screen.dart:173`**
   - Query (nested): `restaurant -> user:user_id (id, name, phone, address, email)`
   - **❌ `address` no existe en `users`**

**¿Por qué pasó?**
Tras el refactor 2025, el campo `address` se movió a:
- `client_profiles.address` (para clientes)
- `restaurants.address` (para restaurantes - dirección del negocio, no del usuario)

---

### **PROBLEMA #2: "Asignando Repartidor..." Nunca Carga** ⏳

**Síntoma:**
Cuando el repartidor acepta la orden, el tracker se queda mostrando **"Asignando repartidor..."** y nunca muestra los datos del repartidor.

**Causa Raíz:**
El mismo problema del query anterior: cuando la orden tiene `delivery_agent_id`, se intenta obtener:
```dart
delivery_agent:delivery_agent_id (
  id,
  name,
  phone
)
```

Pero si el query principal falla (por el campo `address` inexistente), **NUNCA se obtienen los datos del repartidor**, aunque estos campos SÍ existen.

**Resultado:**
- `_order.deliveryAgent` queda en `null`
- El UI muestra "Asignando repartidor..." indefinidamente
- El log muestra: `🚚 [ORDER_DETAILS] Delivery Agent: N/A`

---

### **PROBLEMA #3: Pin de Cliente en el Mapa Mal Ubicado** 📍

**Síntoma:**
En el mini mapa del tracker:
- ✅ Pin del repartidor: OK
- ✅ Pin del restaurant: OK
- ❌ Pin de casa del cliente: **MAL UBICADO**

**Causa Raíz:**
El widget `LiveDeliveryMap` usa `_order.deliveryLatlng` para ubicar la casa del cliente. Este campo viene de `orders.delivery_latlng`.

**¿De dónde viene `delivery_latlng`?**

Revisando `DATABASE_SCHEMA.sql`:
```sql
CREATE TABLE public.orders (
  ...
  delivery_address text NOT NULL,
  delivery_latlng text,          -- ⚠️ FORMATO LEGADO: "lat,lng"
  delivery_lat double precision, -- ✅ FORMATO NUEVO
  delivery_lon double precision, -- ✅ FORMATO NUEVO
  delivery_place_id text,
  delivery_address_structured jsonb,
  ...
);
```

**Problema:**
- `delivery_latlng` (formato `"lat,lng"`) es un **campo legado** que puede estar:
  - ❌ Vacío (`NULL`)
  - ❌ Desactualizado
  - ❌ Con formato incorrecto

- Los campos **correctos** son:
  - ✅ `delivery_lat` (double precision)
  - ✅ `delivery_lon` (double precision)

**Impacto en el Código:**

`lib/widgets/live_delivery_map.dart:34`:
```dart
ll.LatLng? get _dest => _parseLatLng(widget.deliveryLatlng);
```

Si `deliveryLatlng` es `null` o inválido, el pin del cliente **no se muestra** o se muestra en coordenadas incorrectas.

**Código en `order_details_screen.dart:426`:**
```dart
deliveryLatlng: _order.deliveryLatlng,
```

**Solución Propuesta:**
Construir el formato `"lat,lng"` desde `delivery_lat` y `delivery_lon` en el momento de pasar el parámetro al widget.

---

## 🎯 **ESTRATEGIA DE REPARACIÓN**

### **Principio Quirúrgico:**
✅ **NO tocar nada que funcione** (repartidor, restaurant, etc.)  
✅ **Solo modificar queries de órdenes** (remover campos inexistentes)  
✅ **Usar campos correctos del schema** (`delivery_lat` / `delivery_lon`)

---

## 📝 **PLAN DE ACCIÓN**

### **FASE 1: Reparar Queries de Orders** 🔧

#### **Archivo 1: `lib/screens/orders/order_details_screen.dart`**

**Línea 88-152: Query de `_refreshOrderDetails()`**

**ANTES (❌ ROTO):**
```dart
user:user_id (
  id,
  name,
  role,
  email,
  phone,
  address,  // ❌ NO EXISTE
  avatar_url,
  created_at,
  updated_at,
  email_confirm
),
```

**DESPUÉS (✅ REPARADO):**
```dart
user:user_id (
  id,
  name,
  role,
  email,
  phone,
  avatar_url,
  created_at,
  updated_at,
  email_confirm
),
```

**IMPORTANTE:** El modelo `DoaUser.fromJson()` ya tiene fallback para obtener `address` desde `client_profiles`:
```dart
// DoaUser.fromJson() - líneas 104-110
address: (() {
  final fromProfile = clientProfile?['address']?.toString();
  if (fromProfile != null && fromProfile.isNotEmpty) return fromProfile;
  final fromUsers = json['address']?.toString();
  if (fromUsers != null && fromUsers.isNotEmpty) return fromUsers;
  return null;
})(),
```

Por lo tanto, **NO necesitamos hacer JOIN con `client_profiles`** en el query. Simplemente removemos el campo `address` del query de `users`.

---

**Línea 118-124: Nested query de restaurant -> user**

**ANTES (❌ ROTO):**
```dart
user:user_id(
  id,
  name,
  phone,
  address,  // ❌ NO EXISTE
  email
)
```

**DESPUÉS (✅ REPARADO):**
```dart
user:user_id(
  id,
  name,
  phone,
  email
)
```

**NOTA:** La dirección del restaurant viene de `restaurants.address`, no de `users.address`. El campo `_order.restaurant?.formattedAddress` (usado en la línea 468) obtiene la dirección del restaurant correctamente desde `restaurants.address_structured`.

---

#### **Archivo 2: `lib/screens/checkout/order_confirmation_screen.dart`**

**Línea 163-187: Query de track order**

Aplicar los mismos cambios:
1. Remover `address` del query principal de `user:user_id`
2. Remover `address` del nested query `restaurant -> user:user_id`

---

### **FASE 2: Reparar Pin de Cliente en el Mapa** 📍

#### **Archivo: `lib/screens/orders/order_details_screen.dart`**

**Línea 423-426: Pasar coordenadas al LiveDeliveryMap**

**ANTES (❌ USA CAMPO LEGADO):**
```dart
LiveDeliveryMap(
  orderId: _order.id,
  deliveryLatlng: _order.deliveryLatlng,  // ❌ Campo legado "lat,lng"
  restaurantLatlng: ...,
  showClientDestination: ...,
),
```

**DESPUÉS (✅ USA CAMPOS CORRECTOS):**
```dart
LiveDeliveryMap(
  orderId: _order.id,
  deliveryLatlng: (() {
    // Construir formato "lat,lng" desde delivery_lat y delivery_lon
    if (_order.deliveryLat != null && _order.deliveryLon != null) {
      return '${_order.deliveryLat},${_order.deliveryLon}';
    }
    // Fallback al campo legado si existe
    return _order.deliveryLatlng;
  })(),
  restaurantLatlng: ...,
  showClientDestination: ...,
),
```

**Ventaja:** Prioriza los campos correctos de la DB (`delivery_lat`, `delivery_lon`) y solo usa el campo legado como fallback.

---

### **FASE 3: Validación** ✅

**Tests a Realizar:**

1. **Abrir tracker desde checkout:**
   - ✅ Debe abrir sin errores
   - ✅ Debe mostrar datos del cliente correctamente

2. **Repartidor acepta orden:**
   - ✅ El tracker debe mostrar nombre y teléfono del repartidor inmediatamente
   - ✅ NO debe quedarse en "Asignando repartidor..."

3. **Pin de cliente en el mapa:**
   - ✅ Debe aparecer en la ubicación correcta de entrega
   - ✅ No debe aparecer en coordenadas (0,0) o ubicaciones erróneas

---

## 🛡️ **CONSIDERACIONES DE SEGURIDAD**

### **¿Por qué NO agregar JOINs con `client_profiles`?**

❌ **NO hacer:**
```sql
user:user_id (
  ...,
  client_profiles (address, lat, lon)
)
```

**Razones:**
1. **Seguridad:** Los clientes NO deben ver direcciones de otros clientes
2. **Innecesario:** `DoaUser.fromJson()` ya maneja el fallback correctamente
3. **Complejidad:** Agregar JOINs opcionales complica las queries

### **¿Cómo protegemos la dirección del cliente?**

✅ **La dirección del cliente viene de `orders.delivery_address`**, NO de `users.address` ni `client_profiles.address`

✅ **Solo el cliente y el repartidor asignado ven `delivery_address`** (manejado por RLS en Supabase)

✅ **No exponemos `client_profiles` en queries de orders**

---

## 📊 **IMPACTO Y RIESGOS**

### **Impacto:**
- ✅ **Bajo:** Solo se modifican queries y una línea de cálculo
- ✅ **Quirúrgico:** No se tocan funcionalidades de repartidor ni restaurant
- ✅ **Backward Compatible:** Los fallbacks aseguran compatibilidad

### **Riesgos:**
- ⚠️ **Muy Bajo:** Los cambios son solo remover campos inexistentes

### **Rollback:**
- ✅ **Fácil:** Solo revertir los 3 archivos modificados

---

## 🎓 **LECCIONES APRENDIDAS**

### **1. Queries Legacy vs. Refactor**
Tras un refactor de schema, **SIEMPRE** revisar todos los queries de la app para asegurar que no referencien campos eliminados.

### **2. Campos Redundantes**
`delivery_latlng` (formato string) vs. `delivery_lat`/`delivery_lon` (formato double):
- Mantener campos legados puede causar bugs si no se mantienen sincronizados
- **Mejor:** Usar un solo formato (campos separados de tipo double)

### **3. Validación de Coordenadas**
Siempre validar que las coordenadas existan antes de pasarlas a widgets de mapa.

---

## ✅ **CHECKLIST FINAL**

- [ ] Remover `address` de query en `order_details_screen.dart` (user principal)
- [ ] Remover `address` de query en `order_details_screen.dart` (restaurant->user nested)
- [ ] Remover `address` de query en `order_confirmation_screen.dart` (user principal)
- [ ] Remover `address` de query en `order_confirmation_screen.dart` (restaurant->user nested)
- [ ] Modificar `LiveDeliveryMap` call para usar `delivery_lat`/`delivery_lon`
- [ ] Compilar proyecto (`compile_project` tool)
- [ ] Testing manual:
  - [ ] Crear orden → abrir tracker (sin errores)
  - [ ] Repartidor acepta → ver datos del repartidor
  - [ ] Verificar pin de cliente en el mapa

---

## 🚀 **SIGUIENTE PASO**

**¿Proceder con las reparaciones quirúrgicas?**

**Archivos a Modificar:**
1. `lib/screens/orders/order_details_screen.dart` (2 ediciones)
2. `lib/screens/checkout/order_confirmation_screen.dart` (2 ediciones)
3. `lib/screens/orders/order_details_screen.dart` (1 edición para coordenadas del mapa)

**Total:** 5 ediciones en 2 archivos

**Tiempo Estimado:** 5 minutos

---

**¿Aprobado para proceder?** ✅
