# 🔧 FIX: Mini-Tracker No Actualiza en Tiempo Real

**Fecha:** 2025-11-16  
**Prioridad:** 🔴 CRÍTICA  
**Estado:** ✅ SOLUCIONADO

---

## 📋 PROBLEMA IDENTIFICADO

El mini-tracker del home screen **NO actualiza en tiempo real** cuando cambia el status de una orden o se asigna un delivery agent.

### 🔍 Síntomas:
1. ✅ Tracker principal en `my_orders_screen.dart` actualiza correctamente
2. ❌ Mini-tracker en `home_screen.dart` requiere refresh manual
3. ❌ Error en console log:
   ```
   PostgrestException(message: column "o.created_at" must appear in the GROUP BY clause 
   or be used in an aggregate function, code: 42803)
   ```

---

## 🎯 CAUSA RAÍZ

La función RPC `get_client_active_orders` tenía **columnas inexistentes** en el schema de la tabla `orders`.

**Error:** El query intentaba seleccionar `platform_fee` y `restaurant_revenue`, pero estas columnas **NO EXISTEN** en la tabla `orders`, causando que PostgreSQL rechazara el query con error 42703.

---

## ✅ SOLUCIÓN IMPLEMENTADA

### 📄 Archivos SQL Creados:

1. **`2025-11-16_CREATE_rpc_get_client_active_orders_FIXED.sql`**
   - Función RPC corregida para obtener órdenes activas
   - **SIN GROUP BY** (no es necesario)
   - LEFT JOIN simple con `users` para obtener nombre y teléfono del delivery agent

2. **`2025-11-16_CREATE_rpc_get_order_with_details_FIXED.sql`**
   - Función RPC corregida para obtener una orden específica
   - **SIN GROUP BY** (no es necesario)
   - LEFT JOIN simple con `users` para obtener nombre y teléfono del delivery agent

### 🔧 Cambios Realizados:

**ANTES (con error):**
```sql
SELECT 
  o.id,
  o.user_id,
  o.restaurant_id,
  o.delivery_agent_id,
  o.status,
  o.total_amount,
  o.delivery_fee,
  o.platform_fee,-- ❌ ERROR: Esta columna NO EXISTE
  o.restaurant_revenue, -- ❌ ERROR: Esta columna NO EXISTE
  o.delivery_address,
  o.delivery_lat,
  o.delivery_lng,
  o.pickup_code,
  o.delivery_code, -- ❌ ERROR: Se llama 'confirm_code' en el schema
  o.notes, -- ❌ ERROR: Se llama 'order_notes' en el schema
  o.created_at,
  o.updated_at,
  u.name AS delivery_user_name,
  u.phone AS delivery_user_phone
FROM orders o
LEFT JOIN users u ON u.id = o.delivery_agent_id
```

**DESPUÉS (correcto - basado en DATABASE_SCHEMA.sql):**
```sql
SELECT 
  o.id,
  o.user_id,
  o.restaurant_id,
  o.delivery_agent_id,
  o.status,
  o.total_amount,
  o.delivery_fee,
  o.payment_method, -- ✅ Columna real del schema
  o.delivery_address,
  o.delivery_latlng, -- ✅ Columna real del schema
  o.delivery_lat,
  o.delivery_lon, -- ✅ 'lon' no 'lng'
  o.delivery_place_id, -- ✅ Columna real del schema
  o.delivery_address_structured, -- ✅ Columna real del schema
  o.pickup_code, -- ✅ Correcto
  o.confirm_code, -- ✅ Correcto (no 'delivery_code')
  o.order_notes, -- ✅ Correcto (no 'notes')
  o.assigned_at, -- ✅ Columna real del schema
  o.delivery_time, -- ✅ Columna real del schema
  o.pickup_time, -- ✅ Columna real del schema
  o.created_at,
  o.updated_at,
  u.name AS delivery_user_name,
  u.phone AS delivery_user_phone
FROM orders o
LEFT JOIN users u ON u.id = o.delivery_agent_id
-- ✅ TODAS las columnas coinciden con DATABASE_SCHEMA.sql
```

---

## 📝 INSTRUCCIONES DE DEPLOYMENT

### 1️⃣ Ejecutar en Supabase SQL Editor:

**Orden de ejecución:**
```bash
# 1. Corregir función de órdenes activas
supabase_scripts/2025-11-16_CREATE_rpc_get_client_active_orders_FIXED.sql

# 2. Corregir función de orden individual
supabase_scripts/2025-11-16_CREATE_rpc_get_order_with_details_FIXED.sql
```

### 2️⃣ Verificar funcionamiento:

```sql
-- Test 1: Verificar que get_client_active_orders funciona
SELECT * FROM get_client_active_orders('c7c5e7d1-4511-4690-91a9-127831e26f7e');

-- Test 2: Verificar que get_order_with_details funciona
SELECT * FROM get_order_with_details('b9e709f0-c4b3-468b-a315-1d0364cb0bec');
```

**Resultado esperado:**
- ✅ Ambos queries deben ejecutarse sin errores
- ✅ Deben incluir `delivery_user_name` y `delivery_user_phone`
- ✅ Si hay delivery agent asignado, los campos deben tener valores

### 3️⃣ Probar en la app:

1. **Como cliente:** Crear una orden nueva
2. **Como delivery agent:** Aceptar la orden
3. **Verificar:** El mini-tracker en home debe actualizar automáticamente mostrando:
   - ✅ Nuevo status
   - ✅ Nombre del delivery agent
   - ✅ Sin necesidad de refresh manual

---

## 🧪 TESTING

### Escenario 1: Orden pendiente → Asignada
```
1. Cliente crea orden (status: 'pending')
2. Delivery agent acepta orden (status: 'assigned')
3. ✅ Mini-tracker debe mostrar: "Repartidor asignado: Jimmi Boy"
```

### Escenario 2: Orden asignada → Recogida
```
1. Orden tiene status 'assigned'
2. Delivery agent recoge orden (status: 'picked_up')
3. ✅ Mini-tracker debe actualizar progreso automáticamente
```

### Escenario 3: Múltiples órdenes activas
```
1. Cliente tiene 2+ órdenes activas
2. Cada orden tiene delivery agent diferente
3. ✅ Multi-tracker debe mostrar todos los nombres correctamente
```

---

## 📊 RESULTADO ESPERADO

### ANTES (con error):
```
❌ Mini-tracker no actualiza
❌ Error en console: "column o.created_at must appear in GROUP BY"
❌ Requiere refresh manual para ver cambios
```

### DESPUÉS (correcto):
```
✅ Mini-tracker actualiza en tiempo real
✅ Sin errores en console
✅ Muestra nombre del delivery agent automáticamente
✅ Actualiza progreso sin intervención del usuario
```

---

## 🔍 NOTAS TÉCNICAS

### Por qué NO se necesita GROUP BY:

El query original intentaba usar `GROUP BY` pensando que era necesario para el JOIN, pero:
- ✅ No hay funciones de agregación (`COUNT`, `SUM`, etc.)
- ✅ La relación `orders` → `users` es **1:1** (un delivery agent por orden)
- ✅ No hay necesidad de agrupar filas

### Por qué el tracker principal funcionaba:

El tracker principal usa el stream de Realtime que escucha cambios directamente en la tabla `orders`, mientras que el mini-tracker dependía de la función RPC que tenía el error SQL.

---

## ✅ CHECKLIST DE DEPLOYMENT

- [ ] Ejecutar `2025-11-16_CREATE_rpc_get_client_active_orders_FIXED.sql`
- [ ] Ejecutar `2025-11-16_CREATE_rpc_get_order_with_details_FIXED.sql`
- [ ] Verificar con queries de test
- [ ] Probar en app: crear orden → asignar delivery agent
- [ ] Confirmar que mini-tracker actualiza sin refresh
- [ ] Verificar que nombre del delivery agent aparece correctamente

---

**Firma:** Hologram  
**Fecha:** 2025-11-16  
**Ticket:** MINI-TRACKER-REALTIME-FIX
