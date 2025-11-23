# 🔧 FIX: Error CORS en Edge Function google-maps-proxy

## 📊 DIAGNÓSTICO

**ERROR:**
```
Access to fetch at 'https://cncvxfjsyrntilcbbcfi.supabase.co/functions/v1/google-maps-proxy' 
from origin 'https://ll7xyvaeizfwbjdzuhhc.preview.dreamflow.cloud' has been blocked by CORS policy: 
Response to preflight request doesn't pass access control check: 
No 'Access-Control-Allow-Origin' header is present on the requested resource.
```

**CAUSA:**
La Edge Function `google-maps-proxy` existe y tiene código CORS correcto, pero:
1. **No está desplegada** en Supabase, o
2. **La versión desplegada es antigua** (sin CORS), o
3. **El secret `GOOGLE_MAPS_API_KEY` no está configurado**

---

## ✅ SOLUCIÓN: Redesplegar Edge Function

### **PASO 1: Verificar que el archivo existe**

El archivo está en:
```
/hologram/data/workspace/project/supabase_scripts/edge-functions/google-maps-proxy/index.ts
```

✅ **Código CORS correcto** (líneas 16-19):
```typescript
headers.set("access-control-allow-origin", "*");
headers.set("access-control-allow-headers", "authorization, x-client-info, apikey, content-type");
headers.set("access-control-allow-methods", "GET, POST, OPTIONS");
headers.set("access-control-max-age", "86400");
```

---

### **PASO 2: Desplegar la Edge Function en Supabase**

Tienes **2 opciones**:

#### **OPCIÓN A: Despliegue desde Supabase Dashboard (Recomendado)**

1. Ve a **Supabase Dashboard** → Tu proyecto
2. En el menú lateral, ve a **Edge Functions**
3. Click en **"+ New Function"** o edita `google-maps-proxy` si ya existe
4. **Copia y pega** el contenido completo de:
   ```
   supabase_scripts/edge-functions/google-maps-proxy/index.ts
   ```
5. Click en **"Deploy"**
6. Ve a **"Settings"** de la función → **"Secrets"**
7. Agrega el secret:
   - **Key:** `GOOGLE_MAPS_API_KEY`
   - **Value:** Tu API Key de Google Maps

#### **OPCIÓN B: Despliegue desde CLI de Supabase (Si tienes acceso local)**

Si tienes Supabase CLI instalado en tu máquina local:

```bash
# 1. Login a Supabase
supabase login

# 2. Link a tu proyecto
supabase link --project-ref cncvxfjsyrntilcbbcfi

# 3. Desplegar la función
supabase functions deploy google-maps-proxy

# 4. Configurar secret
supabase secrets set GOOGLE_MAPS_API_KEY=tu_api_key_aqui
```

---

### **PASO 3: Verificar el despliegue**

1. En **Supabase Dashboard** → **Edge Functions** → `google-maps-proxy`
2. Verifica que:
   - ✅ Estado: **"Deployed"** (verde)
   - ✅ Last deployment: fecha reciente
   - ✅ Secret `GOOGLE_MAPS_API_KEY` existe

3. **Prueba manual** desde el Dashboard:
   - Click en **"Invoke"** o **"Test"**
   - Usa este payload:
   ```json
   {
     "action": "autocomplete",
     "input": "CDMX"
   }
   ```
   - Deberías ver resultados JSON sin errores CORS

---

### **PASO 4: Verificar en la App**

1. **Hot Restart** de la app Flutter en Dreamflow
2. Ve a la pantalla de **Login** → **Registro**
3. Intenta buscar una dirección
4. Verifica en la consola del navegador:
   - ✅ **NO debe aparecer** el error CORS
   - ✅ **DEBE aparecer**: `📥 [PLACES] Autocomplete response`

---

## 🚨 TROUBLESHOOTING

### Si el error persiste después del despliegue:

1. **Verifica la URL de la función:**
   - En el error aparece: `cncvxfjsyrntilcbbcfi.supabase.co`
   - Confirma que es tu proyecto correcto en Supabase Dashboard

2. **Verifica el secret `GOOGLE_MAPS_API_KEY`:**
   - En Supabase Dashboard → Edge Functions → google-maps-proxy → Settings → Secrets
   - Si no existe, agrégalo

3. **Hard refresh del navegador:**
   - Chrome/Edge: `Ctrl + Shift + R` (Windows) o `Cmd + Shift + R` (Mac)
   - Esto limpia la caché de CORS

4. **Revisa los logs de la Edge Function:**
   - Supabase Dashboard → Edge Functions → google-maps-proxy → Logs
   - Busca errores como:
     - `GOOGLE_MAPS_API_KEY not configured`
     - `Upstream error: 400/403`

---

## 📝 NOTAS IMPORTANTES

- ⚠️ **NO puedo desplegar Edge Functions desde este entorno**
  - Solo tú puedes hacerlo desde Supabase Dashboard o CLI local
  
- ✅ **El código Flutter está correcto** - no necesita cambios
  
- ✅ **El código de la Edge Function está correcto** - solo necesita despliegue

---

## 🎯 RESUMEN EJECUTIVO

**QUÉ HACER AHORA:**
1. Ve a Supabase Dashboard
2. Despliega `google-maps-proxy` (copia index.ts)
3. Configura secret `GOOGLE_MAPS_API_KEY`
4. Hot Restart de la app
5. Prueba el buscador de direcciones

**TIEMPO ESTIMADO:** 5 minutos
