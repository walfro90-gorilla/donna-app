# 🚀 MIGRACIÓN: Flujo de Pago Mejorado con MercadoPago

## 📋 Resumen de Cambios

Se ha implementado un **nuevo flujo de pago** que garantiza que **las órdenes solo se crean después de confirmar el pago** con MercadoPago.

### ❌ Flujo Anterior (INCORRECTO):
1. Usuario hace checkout
2. **App crea la orden en Supabase**
3. App abre MercadoPago
4. Si usuario cancela → **Orden huérfana en la BD** 💥

### ✅ Flujo Nuevo (CORRECTO):
1. Usuario hace checkout
2. **Si pago = efectivo** → crear orden inmediatamente
3. **Si pago = tarjeta** → NO crear orden, solo abrir MercadoPago
4. Usuario completa pago en MercadoPago ✅
5. **Webhook recibe confirmación** y crea la orden automáticamente
6. App muestra pantalla de confirmación con orden creada

---

## 🗄️ PASO 1: Ejecutar Migración SQL en Supabase

### Abrir Supabase SQL Editor:
1. Ve a tu proyecto en [Supabase Dashboard](https://supabase.com/dashboard)
2. Menú lateral → **SQL Editor**
3. Haz clic en **+ New Query**

### Ejecutar este script:

```sql
-- ============================================================================
-- MIGRACIÓN: Flujo de Pago Mejorado
-- ============================================================================

BEGIN;

-- Paso 1: Hacer order_id nullable
ALTER TABLE public.payments
ALTER COLUMN order_id DROP NOT NULL;

-- Paso 2: Añadir columna order_data
ALTER TABLE public.payments
ADD COLUMN IF NOT EXISTS order_data JSONB DEFAULT NULL;

-- Paso 3: Crear índice GIN
CREATE INDEX IF NOT EXISTS idx_payments_order_data 
ON public.payments USING GIN (order_data);

-- Paso 4: Actualizar constraint de status
ALTER TABLE public.payments
DROP CONSTRAINT IF EXISTS payments_status_check;

ALTER TABLE public.payments
ADD CONSTRAINT payments_status_check 
CHECK (status = ANY (ARRAY['pending'::text, 'succeeded'::text, 'failed'::text, 'completed'::text]));

COMMIT;
```

### Verificar que se aplicó correctamente:

```sql
SELECT 
  column_name, 
  data_type, 
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'payments'
  AND column_name IN ('order_id', 'order_data', 'status')
ORDER BY ordinal_position;
```

**Resultado esperado:**
- `order_id` → `is_nullable = YES`
- `order_data` → `data_type = jsonb`, `is_nullable = YES`
- `status` → debe aceptar `'completed'`

---

## 🔧 PASO 2: Desplegar Edge Functions Actualizadas

Las siguientes Edge Functions han sido actualizadas:

1. **`create-payment`** - Ahora acepta `order_data` y lo guarda en la tabla `payments`
2. **`mercadopago-webhook`** - Ahora crea la orden automáticamente si detecta `order_data` tras pago exitoso

### Desplegar en Supabase:

```bash
# Desde la raíz del proyecto
supabase functions deploy create-payment
supabase functions deploy mercadopago-webhook
```

---

## ✅ PASO 3: Probar el Flujo Completo

### Test 1: Pago con Efectivo (comportamiento sin cambios)
1. Añade productos al carrito
2. Ir a checkout
3. Selecciona **"Cash on Delivery"**
4. Completa el pedido
5. **Resultado esperado:** Orden se crea inmediatamente

### Test 2: Pago con Tarjeta (NUEVO FLUJO)
1. Añade productos al carrito
2. Ir a checkout
3. Selecciona **"Credit/Debit Card"**
4. Completa el pedido
5. Se abre MercadoPago en nueva pestaña (web) o WebView (móvil)
6. **Opciones:**
   - ✅ **Completar pago** → Orden se crea automáticamente por webhook
   - ❌ **Cancelar** → NO se crea orden (correcto)
7. Al regresar a la app, se muestra confirmación con orden creada

### Test 3: Verificar en Base de Datos

```sql
-- Ver payments recientes con order_data
SELECT 
  id,
  order_id,
  status,
  mp_preference_id,
  order_data IS NOT NULL as has_order_data,
  created_at
FROM public.payments
ORDER BY created_at DESC
LIMIT 10;

-- Ver órdenes recientes con payment_status = 'paid'
SELECT 
  id,
  client_id,
  restaurant_id,
  total_amount,
  payment_status,
  status,
  created_at
FROM public.orders
WHERE payment_status = 'paid'
ORDER BY created_at DESC
LIMIT 10;
```

---

## 🐛 Troubleshooting

### Error: "Payment record no encontrado"
**Causa:** El webhook no encuentra el payment por `mp_preference_id`

**Solución:**
1. Verifica que la migración SQL se aplicó correctamente
2. Verifica que las Edge Functions se desplegaron
3. Revisa logs del webhook:
   ```bash
   supabase functions logs mercadopago-webhook --tail
   ```

### Error: "order_id cannot be null"
**Causa:** La migración SQL no se aplicó

**Solución:**
1. Ejecuta la migración SQL en Supabase SQL Editor
2. Verifica con la query de verificación

### Orden no se crea tras pago exitoso
**Causa:** El webhook no está recibiendo notificaciones o hay error al crear orden

**Solución:**
1. Revisa logs del webhook
2. Verifica que `order_data` tiene todos los campos necesarios:
   ```sql
   SELECT order_data 
   FROM public.payments 
   WHERE order_data IS NOT NULL 
   ORDER BY created_at DESC 
   LIMIT 1;
   ```

---

## 📁 Archivos Modificados

### Flutter (App)
- ✅ `lib/screens/checkout/checkout_screen.dart` - Flujo bifurcado efectivo/tarjeta
- ✅ `lib/screens/checkout/mercadopago_checkout_screen.dart` - Acepta `orderData` y busca orden creada
- ✅ `lib/services/mercadopago_service.dart` - Envía `order_data` a Edge Function

### Supabase (Backend)
- ✅ `supabase/functions/create-payment/index.ts` - Guarda `order_data` en payments
- ✅ `supabase/functions/mercadopago-webhook/index.ts` - Crea orden tras pago exitoso

### SQL (Migraciones)
- ✅ `sql_migrations/2025-01-17_MAKE_order_id_nullable_in_payments.sql`
- ✅ `sql_migrations/2025-01-17_ADD_order_data_to_payments.sql`
- ✅ `EJECUTAR_MIGRACION_PAGOS.sql` - Script consolidado

### Schema
- ✅ `supabase_scripts/DATABASE_SCHEMA.sql` - Actualizado con cambios

---

## 🎯 Próximos Pasos

1. ✅ **EJECUTAR** migración SQL en Supabase
2. ✅ **DESPLEGAR** Edge Functions actualizadas
3. ✅ **PROBAR** flujo completo en la app
4. ✅ **VERIFICAR** que no se crean órdenes huérfanas al cancelar pagos

---

**¿Listo para probar?** 🚀
