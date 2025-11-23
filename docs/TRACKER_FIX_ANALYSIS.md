# 🔧 ANÁLISIS QUIRÚRGICO: Error en Trackers

## 📋 PROBLEMA IDENTIFICADO

**Error en Console Log:**
```
ERROR: 42703: column r.delivery_time does not exist
PostgrestException(message: column r.delivery_time does not exist, code: 42703)
```

**Síntoma:** 
- ❌ Mini-tracker NO se actualiza en tiempo real
- ❌ Tracker principal muestra error y NO refleja información de la orden

---

## 🔍 CAUSA RAÍZ

Las funciones RPC `get_order_full_details` y `get_client_active_orders` están intentando acceder a columnas que **NO EXISTEN** en la tabla `restaurants`:

### ❌ Columnas INCORRECTAS (líneas 77, 78, 251, 252):
```sql
'delivery_time', r.delivery_time,    -- NO EXISTE
'delivery_fee', r.delivery_fee,      -- NO EXISTE
```

### ✅ Columnas CORRECTAS según DATABASE_SCHEMA.sql:

**Tabla `restaurants` (líneas 281-314):**
- ✅ `estimated_delivery_time_minutes` (integer) - Tiempo estimado de entrega
- ✅ `min_order_amount` (numeric) - Monto mínimo de orden
- ✅ `delivery_radius_km` (numeric) - Radio de entrega
- ❌ **NO** tiene `delivery_time`
- ❌ **NO** tiene `delivery_fee`

**Tabla `orders` (líneas 204-235):**
- ✅ `delivery_time` (timestamp) - Hora de entrega
- ✅ `delivery_fee` (numeric) - Tarifa de entrega

**Conclusión:** Se están mezclando campos de `orders` dentro del objeto `restaurant`.

---

## ✅ SOLUCIÓN QUIRÚRGICA

### Paso 1: Corregir `get_order_full_details` (líneas 73-78)

**REMOVER:**
```sql
'delivery_time', r.delivery_time,
'delivery_fee', r.delivery_fee,
```

**AGREGAR:**
```sql
'estimated_delivery_time_minutes', r.estimated_delivery_time_minutes,
'delivery_radius_km', r.delivery_radius_km,
```

### Paso 2: Corregir `get_client_active_orders` (líneas 247-252)

**REMOVER:**
```sql
'delivery_time', r.delivery_time,
'delivery_fee', r.delivery_fee,
```

**AGREGAR:**
```sql
'estimated_delivery_time_minutes', r.estimated_delivery_time_minutes,
'delivery_radius_km', r.delivery_radius_km,
```

### Paso 3: Crear script SQL v3 CORREGIDO

Crear `2025-11-17_DEPLOY_optimized_tracker_rpcs_v3.sql` con las correcciones aplicadas.

---

## 📊 VERIFICACIÓN

Después de aplicar el script v3:

1. ✅ Verificar que NO hay errores de columnas inexistentes
2. ✅ Verificar que ambas funciones devuelven JSON correctamente
3. ✅ Verificar que `DoaRestaurant.fromJson()` puede deserializar el JSON
4. ✅ Verificar que el mini-tracker se actualiza en tiempo real
5. ✅ Verificar que el tracker principal muestra toda la información

---

## 🎯 RESULTADO ESPERADO

- ✅ **Mini-tracker:** Se actualiza automáticamente cuando el status de la orden cambia
- ✅ **Tracker principal:** Muestra información completa de restaurant, delivery, items
- ✅ **Ambos trackers:** Consumen la misma fuente de datos (RPC functions)
- ✅ **Tiempo real:** El `RealtimeService` detecta cambios y actualiza automáticamente

---

## 📝 NOTAS

- El problema NO está en el código Dart (RealtimeService, Widgets)
- El problema ESTÁ en las funciones SQL que no coinciden con el schema real
- La solución es QUIRÚRGICA: solo corregir las columnas incorrectas
