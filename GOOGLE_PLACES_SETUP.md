# Configuración de Google Places API - Doa Repartos

## ✅ Checklist de Implementación

### 1️⃣ Backend (Supabase)

#### A. Ejecutar Scripts SQL
En el **SQL Editor** de Supabase, ejecuta el siguiente script para añadir las columnas JSONB:

```bash
supabase_scripts/sql/07_add_address_structured_columns.sql
```

Este script:
- Añade `delivery_address_structured` (JSONB) a la tabla `orders`
- Añade `address_structured` (JSONB) a la tabla `restaurants`
- (Opcional) Convierte `users.current_location` a tipo PostGIS `GEOGRAPHY(Point, 4326)`

#### B. Verificar la Edge Function `maps-proxy`
La Edge Function debe estar desplegada y tener acceso al secreto `GOOGLE_MAPS_API_KEY`.

**Desplegar la función:**
```bash
supabase functions deploy maps-proxy
```

**Verificar el secreto:**
En Supabase Console → **Edge Functions** → **Secrets**, asegúrate de que existe:
- Nombre: `GOOGLE_MAPS_API_KEY`
- Valor: Tu clave de API de Google Maps

#### C. Habilitar APIs en Google Cloud Console
En [Google Cloud Console](https://console.cloud.google.com/):

1. **Places API (new)** → ENABLE
2. **Geocoding API** → ENABLE
3. **Address Validation API** → ENABLE (opcional pero recomendado)

**Configurar restricciones de API Key:**
- Por IP: añade la IP de los servidores de Supabase Edge Functions (si es posible)
- Por HTTP referrer: no aplica para Edge Functions
- Por restricción de API: limita a Places, Geocoding, Address Validation

---

### 2️⃣ Frontend (Flutter)

#### A. Dependencias añadidas
Ya se añadieron a `pubspec.yaml`:
```yaml
google_maps_flutter: ^2.9.0
google_maps_flutter_web: ^0.5.10
```

#### B. Archivos actualizados

1. **`lib/services/places_service.dart`**
   - ✅ Autocomplete: buscar direcciones
   - ✅ Place Details: obtener coordenadas de un place_id
   - ✅ Geocode: convertir texto a coordenadas
   - ✅ Reverse Geocode: convertir coordenadas a texto + componentes estructurados
   - ✅ Validate Address: validar y estructurar dirección (opcional)

2. **`lib/widgets/address_picker_modal.dart`** (NUEVO)
   - Widget completo para el flujo: búsqueda → mapa con pin arrastrable → confirmación
   - Devuelve `AddressPickResult` con:
     - `formattedAddress`: dirección de texto final
     - `lat`, `lon`: coordenadas finales
     - `placeId`: ID de Google Places (si aplica)
     - `addressStructured`: componentes JSONB (calle, ciudad, estado, etc.)

3. **`lib/screens/checkout/checkout_screen.dart`**
   - ✅ Usa `AddressPickerModal` en lugar del modal simple
   - ✅ Guarda en la orden:
     - `delivery_address`: texto
     - `delivery_lat`, `delivery_lon`: coordenadas
     - `delivery_place_id`: place_id de Google
     - `delivery_address_structured`: JSONB con componentes

4. **`supabase_scripts/edge-functions/maps-proxy/index.ts`**
   - ✅ Maneja 5 acciones:
     - `autocomplete`: Autocomplete de Places
     - `place_details`: Detalles de un place_id
     - `geocode`: Texto → coordenadas
     - `reverse_geocode`: Coordenadas → texto + componentes estructurados
     - `validate_address`: Validar dirección (Address Validation API)

---

### 3️⃣ Flujo de Usuario (UX)

**En Checkout:**
1. Usuario toca el icono de búsqueda 🔍 en el campo de dirección
2. Se abre el modal de `AddressPickerModal`:
   - **Paso 1:** Búsqueda con Autocomplete
   - **Paso 2:** Selección de resultado → se abre mapa con pin en esa ubicación
   - **Paso 3:** Usuario arrastra el pin para ajustar la ubicación exacta
   - **Paso 4:** Confirmar → se hace Reverse Geocode para obtener dirección precisa + componentes
   - **Paso 5:** Se cierra el modal y se llenan todos los campos en el checkout

3. Usuario confirma el pedido
4. Se guarda en la orden:
   - Dirección de texto (`delivery_address`)
   - Coordenadas (`delivery_lat`, `delivery_lon`)
   - Place ID (`delivery_place_id`)
   - Componentes estructurados (`delivery_address_structured`) en JSONB

---

### 4️⃣ Testing

#### Test 1: Autocomplete
1. Ve a **Checkout** en la app
2. Toca el icono de búsqueda 🔍
3. Escribe "Oaxaca" → deberías ver sugerencias de Google Places
4. Verifica en los logs: `[PLACES] Autocomplete results=X`

#### Test 2: Mapa + Pin Arrastrable
1. Selecciona una sugerencia
2. Debería abrirse un mapa con un pin rojo
3. Arrastra el pin a otra ubicación
4. Toca "Confirmar Ubicación"
5. Verifica en los logs: `[CHECKOUT] Coordenadas: lat=X, lon=Y`

#### Test 3: Guardar en Orden
1. Completa el checkout y crea una orden
2. Ve a Supabase → **Table Editor** → `orders`
3. Busca tu orden más reciente y verifica:
   - `delivery_address`: texto completo
   - `delivery_lat`, `delivery_lon`: números
   - `delivery_place_id`: string con formato `ChIJ...`
   - `delivery_address_structured`: JSON con componentes (street, city, state, etc.)

---

### 5️⃣ Logs Estratégicos

Los logs te ayudarán a detectar problemas:

```
🔎 [PLACES] Autocomplete request => {...}
📥 [PLACES] Autocomplete response => {...}
✅ [PLACES] Autocomplete results=5

🔎 [PLACES] PlaceDetails request => {...}
📥 [PLACES] PlaceDetails response => {...}

🔎 [PLACES] ReverseGeocode request => {...}
📥 [PLACES] ReverseGeocode response => {...}

✅ [CHECKOUT] Dirección confirmada: Calle Principal 123, Oaxaca
✅ [CHECKOUT] Coordenadas: lat=17.073, lon=-96.726
✅ [CHECKOUT] Structured: {street_number: 123, route: Calle Principal, ...}

✅ [CHECKOUT] Datos completos de entrega guardados: lat=17.073, lon=-96.726, structured=true
```

**Si ves errores:**
- `REQUEST_DENIED`: la API no está habilitada o la clave tiene restricciones
- `OVER_QUERY_LIMIT`: superaste el límite gratuito de Google
- `ZERO_RESULTS`: no hay resultados para esa búsqueda
- `ClientException: Failed to fetch`: la Edge Function no está desplegada o no tiene acceso al secreto

---

### 6️⃣ Próximos Pasos (Opcional)

#### A. Usar Address Validation API
En `address_picker_modal.dart`, línea ~150, descomenta:
```dart
final validationResult = await PlacesService.validateAddress(finalAddress);
if (validationResult != null) {
  final validatedAddr = validationResult['formatted_address']?.toString();
  if (validatedAddr != null && validatedAddr.isNotEmpty) {
    finalAddress = validatedAddr;
  }
  structured = validationResult['postal_address'] as Map<String, dynamic>?;
}
```

#### B. Añadir Places a Restaurantes
Aplica el mismo flujo en `restaurant_profile_screen.dart` para que los restaurantes también puedan seleccionar su ubicación con mapa y pin.

#### C. Calcular Distancias
Usa las coordenadas para calcular distancias:
```dart
import 'package:geolocator/geolocator.dart';

double distanceInMeters = Geolocator.distanceBetween(
  restaurantLat, restaurantLon,
  deliveryLat, deliveryLon,
);
```

#### D. Mostrar Mapa en el Detalle de Orden
En `order_details_screen.dart`, usa `GoogleMap` para mostrar la ubicación de entrega en el mapa.

---

## 📚 Referencias

- [Google Places API (new)](https://developers.google.com/maps/documentation/places/web-service/overview)
- [Google Geocoding API](https://developers.google.com/maps/documentation/geocoding/overview)
- [Google Address Validation API](https://developers.google.com/maps/documentation/address-validation/overview)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [google_maps_flutter](https://pub.dev/packages/google_maps_flutter)

---

## 🎯 Resumen

**Implementación completada:**
- ✅ Edge Function `maps-proxy` actualizada con 5 endpoints
- ✅ `PlacesService` con todos los métodos (autocomplete, details, geocode, reverse geocode, validate)
- ✅ `AddressPickerModal` con búsqueda + mapa + pin arrastrable
- ✅ `CheckoutScreen` integrado con el nuevo flujo
- ✅ Guardar datos completos en BD: texto, coordenadas, place_id, componentes JSONB
- ✅ Script SQL para añadir columnas JSONB
- ✅ Logs estratégicos en cada paso

**Pendiente por tu parte:**
1. Ejecutar el script SQL `07_add_address_structured_columns.sql` en Supabase
2. Verificar que la Edge Function `maps-proxy` está desplegada
3. Confirmar que el secreto `GOOGLE_MAPS_API_KEY` existe y es válido
4. Habilitar las APIs en Google Cloud Console
5. Probar el flujo completo en la app

---

✨ **Listo para probar!** Si tienes problemas, revisa los logs en la consola de la app.
