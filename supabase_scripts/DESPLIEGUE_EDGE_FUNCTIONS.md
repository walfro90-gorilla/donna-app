# 🚀 Despliegue de Edge Functions - Google Maps Proxy

## ⚠️ ACCIÓN REQUERIDA

La aplicación ha sido actualizada para usar **`google-maps-proxy`** (Google Maps API) en lugar del servicio anterior.

## 📋 Pasos para Desplegar

### 1. Verificar que la API Key está configurada en Supabase

```bash
# Verificar que GOOGLE_MAPS_API_KEY está configurada
supabase secrets list
```

Si NO aparece, configurarla:

```bash
supabase secrets set GOOGLE_MAPS_API_KEY=tu_api_key_aqui
```

### 2. Desplegar la nueva Edge Function

```bash
# Desde la raíz del proyecto
cd supabase_scripts

# Desplegar google-maps-proxy
supabase functions deploy google-maps-proxy

# Verificar que se desplegó correctamente
supabase functions list
```

### 3. (Opcional) Eliminar la función antigua

Una vez que confirmes que `google-maps-proxy` funciona correctamente:

```bash
# Eliminar la función antigua maps-proxy
supabase functions delete maps-proxy

# Eliminar la carpeta local (ya no se usa)
rm -rf edge-functions/maps-proxy
```

---

## 🔍 Verificar que funciona

Después del despliegue:

1. Abre la app en Dreamflow
2. Ve a la pantalla de Checkout
3. Haz clic en el botón de búsqueda (🔍) junto al campo de dirección
4. Escribe "oasis" y verifica que aparezcan sugerencias de Google Maps
5. Selecciona una dirección y confirma en el mapa con el pin arrastrable

**Resultado esperado**: Sin errores de "Photon status 400" — todo debe usar Google Maps API.

---

## 🛠 Solución de Problemas

### Error: "GOOGLE_MAPS_API_KEY is not configured"

**Causa**: El secret no está configurado en Supabase.

**Solución**:
```bash
supabase secrets set GOOGLE_MAPS_API_KEY=tu_api_key_de_google_console
```

### Error: "Unknown or missing 'action'"

**Causa**: El payload enviado desde Flutter no es el esperado.

**Solución**: Verificar que `places_service.dart` esté llamando a `google-maps-proxy` y no a `maps-proxy`.

### Error: "Upstream error: 400" o "REQUEST_DENIED"

**Causa**: La API Key de Google no tiene los permisos correctos o no está habilitada.

**Solución**:
1. Ir a [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
2. Verificar que la API Key tenga habilitadas:
   - Places API (New)
   - Geocoding API
   - Address Validation API (opcional)
3. Verificar que NO haya restricciones de IP o dominio que bloqueen las llamadas desde Supabase Edge Functions

---

## 📌 Estado Actual

- ✅ **Código Flutter** actualizado para usar `google-maps-proxy`
- ✅ **Edge Function** `google-maps-proxy` creada en `supabase_scripts/edge-functions/`
- ⏳ **Despliegue pendiente**: Necesitas correr `supabase functions deploy google-maps-proxy`
- 🗑️ **maps-proxy antigua**: Se puede eliminar después de confirmar que la nueva funciona

---

## 📝 Notas Técnicas

### Flujo de Geolocalización Implementado

1. **Autocomplete** (con sessionToken para optimizar costos):
   - Usuario escribe → Places Autocomplete API
   - Retorna lista de sugerencias con `place_id`

2. **Place Details** (con sessionToken para billing):
   - Usuario selecciona → Place Details API
   - Retorna `lat`, `lon`, `formatted_address`, `address_components`

3. **Mapa Interactivo**:
   - Muestra pin arrastrable en `lat/lon` inicial
   - Usuario ajusta posición exacta del pin

4. **Reverse Geocode**:
   - Al confirmar → Geocoding API (reverse)
   - Retorna dirección precisa de la posición final del pin

5. **Persistencia**:
   - Se guarda en `orders` tabla:
     - `delivery_address` (texto)
     - `delivery_lat`, `delivery_lon` (coordenadas)
     - `delivery_place_id` (Google place_id)
     - `delivery_address_structured` (JSON con componentes)

### Ventajas del Nuevo Flujo

- ✅ **Preciso**: Coordenadas exactas desde Google Maps
- ✅ **Flexible**: Pin arrastrable para ajuste fino
- ✅ **Estructurado**: Componentes de dirección parseados (calle, ciudad, estado, CP)
- ✅ **Optimizado**: sessionToken reduce costos de billing en Google Places API
- ✅ **Confiable**: Google Maps API en lugar de servicios gratuitos limitados

---

## 🔗 Referencias

- [Google Places API Documentation](https://developers.google.com/maps/documentation/places/web-service/overview)
- [Supabase Edge Functions Docs](https://supabase.com/docs/guides/functions)
- [Session Tokens (Places API)](https://developers.google.com/maps/documentation/places/web-service/session-tokens)
