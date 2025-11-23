# 🚨 ACCIÓN REQUERIDA: Desplegar Edge Function

## ⚠️ Error Actual

Si ves este error en la app:

```
Error al buscar: Photon status 400: {"lang":{"message":"Language is not supported..."}}
```

**Causa**: La nueva Edge Function `google-maps-proxy` NO está desplegada en Supabase.

---

## 📋 Solución Rápida (3 pasos)

### Paso 1: Verificar API Key

Asegúrate de que la API Key de Google Maps está configurada en Supabase:

```bash
supabase secrets list
```

Si NO aparece `GOOGLE_MAPS_API_KEY`, configúrala:

```bash
supabase secrets set GOOGLE_MAPS_API_KEY=TU_CLAVE_DE_GOOGLE_AQUI
```

### Paso 2: Desplegar la Edge Function

Desde la carpeta `supabase_scripts`:

```bash
cd supabase_scripts
supabase functions deploy google-maps-proxy
```

### Paso 3: Verificar el Despliegue

```bash
supabase functions list
```

Deberías ver `google-maps-proxy` en la lista.

---

## 🔍 Verificación en la App

1. Abre la app en Dreamflow
2. Ve a **Checkout**
3. Haz clic en el ícono de búsqueda (🔍) en el campo de dirección
4. Escribe "oasis" o cualquier dirección
5. **Resultado esperado**: Lista de sugerencias de Google Maps
6. **Si falla**: Verifica los pasos anteriores

---

## 🛠 Troubleshooting

### "Function google-maps-proxy not found"

La función no está desplegada. Ejecuta:

```bash
supabase functions deploy google-maps-proxy
```

### "GOOGLE_MAPS_API_KEY is not configured"

El secret no está configurado. Ejecuta:

```bash
supabase secrets set GOOGLE_MAPS_API_KEY=tu_api_key_aqui
```

### "REQUEST_DENIED" o "API key not valid"

1. Ve a [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
2. Selecciona tu proyecto
3. Ve a "APIs y Servicios" > "Credenciales"
4. Verifica que tu API Key tenga habilitadas:
   - ✅ Places API (New)
   - ✅ Geocoding API
   - ✅ Maps JavaScript API
5. Verifica que NO haya restricciones de IP que bloqueen llamadas desde Supabase

### "Photon status 400" (el error actual)

La función `maps-proxy` antigua todavía está activa. Después de desplegar `google-maps-proxy` correctamente, puedes eliminar la antigua:

```bash
supabase functions delete maps-proxy
```

---

##  📝 Archivos Relevantes

- **Edge Function**: `/supabase_scripts/edge-functions/google-maps-proxy/index.ts`
- **Flutter Service**: `/lib/services/places_service.dart`
- **Widget Modal**: `/lib/widgets/address_picker_modal.dart`
- **Checkout Screen**: `/lib/screens/checkout/checkout_screen.dart`

---

## 🎯 Flujo Implementado

1. **Autocomplete**: Usuario escribe → Google Places Autocomplete API
2. **Place Details**: Usuario selecciona → Google Places Details API
3. **Mapa Interactivo**: Pin arrastrable para ajuste fino
4. **Reverse Geocode**: Al confirmar → Google Geocoding API
5. **Persistencia**: Guarda `delivery_lat`, `delivery_lon`, `delivery_place_id`, y `delivery_address_structured`

---

## 🔗 Referencias

- [Guía Completa de Despliegue](./supabase_scripts/DESPLIEGUE_EDGE_FUNCTIONS.md)
- [Google Maps Platform](https://console.cloud.google.com/google/maps-apis/)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
