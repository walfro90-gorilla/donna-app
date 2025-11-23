# 🚀 Deployment Instructions: google-maps-proxy

## 📋 Pre-requisitos
1. ✅ Secret `GOOGLE_MAPS_API_KEY` configurado en Supabase Edge Functions
2. ✅ Places API, Geocoding API y Address Validation API habilitadas en Google Cloud Console

## 🔧 Deployment Manual

Desde tu terminal local (NO desde Dreamflow), ejecutá:

```bash
# 1. Navegá a la raíz del proyecto
cd /path/to/project

# 2. Desplegá la Edge Function
supabase functions deploy google-maps-proxy

# 3. Verificá el deployment
supabase functions list
```

## 🧪 Testing

Una vez desplegado, podés probar desde la consola de Supabase o con curl:

```bash
curl -X POST https://cncvxfjsyrntilcbbcfi.supabase.co/functions/v1/google-maps-proxy \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"action":"autocomplete","input":"oasis","language":"es"}'
```

## 📊 Monitoring

Verificá los logs en:
- Supabase Dashboard → Edge Functions → google-maps-proxy → Logs

Los logs incluyen:
- Todas las requests con método y action
- URLs construidas (con API key oculta)
- Errores upstream de Google Maps API

## 🔄 Cambios Recientes

### v2 - Fix TypeError "Invalid URL"
- ✅ Corregido: URLs ahora usan backticks correctos para interpolación
- ✅ Añadido: Validación de API_KEY antes de construir URLs
- ✅ Mejorado: Logging detallado en todos los endpoints
- ✅ Mejorado: Manejo de errores upstream con mensajes descriptivos
