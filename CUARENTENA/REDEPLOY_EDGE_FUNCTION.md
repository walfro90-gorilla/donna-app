# 🚀 REDESPLEGAR EDGE FUNCTION: create-payment

## ⚠️ PROBLEMA DETECTADO

El Edge Function `create-payment` desplegado en Supabase **NO coincide** con el código local actualizado.

**Versión desplegada (ANTIGUA):**
```typescript
if (!order_id || !amount || !description || !email) {
  throw new Error('Faltan parámetros requeridos: order_id, amount, description, email')
}
```

**Versión local (CORRECTA):**
```typescript
if (!amount || !description || !email) {
  throw new Error('Faltan parámetros requeridos: amount, description, email')
}
```

---

## 🔧 SOLUCIÓN: Redesplegar Edge Function

### **Opción 1: Desde Supabase CLI (RECOMENDADO)**

```bash
cd /path/to/project
supabase functions deploy create-payment
```

### **Opción 2: Desde Supabase Dashboard**

1. **Abre tu proyecto en Supabase Dashboard**
   - https://supabase.com/dashboard/project/[TU_PROJECT_ID]/functions

2. **Navega a Edge Functions**
   - Menú lateral → "Edge Functions"

3. **Elimina la función actual** (si existe)
   - Click en "create-payment"
   - Click en "Delete Function"

4. **Crea nueva función**
   - Click en "New Function"
   - Nombre: `create-payment`
   - Copia y pega el contenido de `/supabase/functions/create-payment/index.ts`

5. **Deploy**
   - Click en "Deploy"

---

## 📋 VERIFICACIÓN

Después de redesplegar, prueba de nuevo el flujo de pago con tarjeta. Deberías ver estos logs:

```
✅ [CREATE-PAYMENT] order_data presente - orden se creará después del pago exitoso
✅ [CREATE-PAYMENT] Cliente: [USER_ID]
✅ [CREATE-PAYMENT] Restaurante: [RESTAURANT_ID]
```

---

## ❓ SI SIGUES TENIENDO PROBLEMAS

Si después de redesplegar sigues viendo el error, ejecuta este query en el SQL Editor de Supabase para verificar que la función se desplegó correctamente:

```sql
-- Verificar última actualización de la función
SELECT 
  name,
  created_at,
  updated_at,
  version
FROM supabase_functions.migrations
WHERE name = 'create-payment'
ORDER BY created_at DESC
LIMIT 1;
```
