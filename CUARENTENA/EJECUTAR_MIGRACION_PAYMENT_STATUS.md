# 🚀 MIGRACIÓN: Agregar columna payment_status

## ⚠️ IMPORTANTE: DEBES EJECUTAR ESTA MIGRACIÓN

El sistema de pagos con MercadoPago requiere la columna `payment_status` en la tabla `orders` para funcionar correctamente.

---

## 📋 PASOS PARA EJECUTAR LA MIGRACIÓN

### 1️⃣ **Abrir Supabase SQL Editor**
```
https://supabase.com/dashboard/project/TU_PROJECT_ID/sql
```

### 2️⃣ **Copiar y ejecutar el SQL**

Abre el archivo:
```
sql_migrations/07_add_payment_status_column.sql
```

Copia TODO el contenido y pégalo en el SQL Editor de Supabase.

### 3️⃣ **Ejecutar la migración**

Haz click en el botón **"RUN"** en Supabase.

### 4️⃣ **Verificar que funcionó**

Ejecuta esta query para verificar:
```sql
SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name = 'orders' 
  AND column_name = 'payment_status';
```

Deberías ver:
```
column_name     | data_type | column_default
payment_status  | text      | 'pending'::text
```

---

## ✅ DESPUÉS DE LA MIGRACIÓN

Una vez ejecutada la migración, **RE-DESPLIEGA** los Edge Functions:

### **Actualizar webhook de MercadoPago:**
```bash
# En tu terminal local (si tienes Supabase CLI)
supabase functions deploy mercadopago-webhook
```

O manualmente en el dashboard de Supabase:
1. Ve a **Edge Functions** → **mercadopago-webhook**
2. Copia el contenido de `/supabase/functions/mercadopago-webhook/index.ts`
3. Pégalo en el editor
4. Haz click en **Deploy**

---

## 🔍 QUÉ HACE ESTA MIGRACIÓN

1. **Agrega la columna `payment_status`** con valores permitidos:
   - `pending` - Pago pendiente (efectivo, o tarjeta sin confirmar)
   - `paid` - Pago completado
   - `failed` - Pago fallido
   - `refunded` - Pago reembolsado

2. **Establece valores por defecto** para órdenes existentes:
   - `cash` → `pending`
   - `card` → `paid` (asume pagos legacy completados)

3. **Crea índices** para optimizar búsquedas de órdenes por estado de pago

---

## 🚨 SI NO EJECUTAS LA MIGRACIÓN

El sistema funcionará con un **fallback temporal**:
- Usa `payment_method='card'` para identificar órdenes pagadas
- **Menos preciso** porque no distingue entre tarjeta pendiente y tarjeta pagada

Pero **DEBES ejecutar la migración** para el funcionamiento completo del sistema.
