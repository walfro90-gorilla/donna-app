# 🚀 DEPLOYMENT: Corrección Quirúrgica de Trackers

## 📋 RESUMEN EJECUTIVO

**Problema:** Ambos trackers (mini y principal) fallaban porque las funciones RPC intentaban acceder a columnas inexistentes en la tabla `restaurants`.

**Solución:** Script SQL v3 que corrige las columnas según el `DATABASE_SCHEMA.sql` real.

---

## ✅ ARCHIVOS CREADOS

### 1. Análisis del Problema
- **`docs/TRACKER_FIX_ANALYSIS.md`** - Análisis detallado de la causa raíz

### 2. Script SQL Corregido
- **`supabase_scripts/2025-11-17_DEPLOY_optimized_tracker_rpcs_v3.sql`** - Script listo para deployment

---

## 🔧 CAMBIOS REALIZADOS

### Columnas Corregidas en Ambas Funciones RPC:

#### ❌ REMOVIDO (NO EXISTEN EN `restaurants`):
```sql
'delivery_time', r.delivery_time,    -- ❌ Esta columna NO existe
'delivery_fee', r.delivery_fee,      -- ❌ Esta columna NO existe
```

#### ✅ AGREGADO (SEGÚN DATABASE_SCHEMA.sql):
```sql
'estimated_delivery_time_minutes', r.estimated_delivery_time_minutes,  -- ✅ Existe
'delivery_radius_km', r.delivery_radius_km,                           -- ✅ Existe
```

---

## 📊 FUNCIONES RPC CORREGIDAS

### 1. `get_order_full_details(order_id uuid)`
**Propósito:** Obtener una orden específica con toda la información relacionada.

**Retorna:** JSON completo con:
- ✅ Orden completa (todos los campos de `orders`)
- ✅ Restaurant completo con user info
- ✅ Delivery agent completo con profile info
- ✅ Order items completos con productos

**Uso en el código:**
```dart
// RealtimeService línea 565
final response = await SupabaseConfig.client
    .rpc('get_order_full_details', params: {'order_id_param': orderId});
final order = DoaOrder.fromJson(response as Map);
```

### 2. `get_client_active_orders(client_id uuid)`
**Propósito:** Obtener todas las órdenes activas del cliente.

**Retorna:** Array JSON de órdenes completas.

**Status considerados "activos":**
- `pending`, `confirmed`, `in_preparation`, `preparing`
- `ready_for_pickup`, `assigned`, `picked_up`
- `on_the_way`, `in_transit`

**Uso en el código:**
```dart
// RealtimeService línea 610
final response = await SupabaseConfig.client
    .rpc('get_client_active_orders', params: {'client_id_param': user.id});
final orders = (response as List)
    .map((json) => DoaOrder.fromJson(json))
    .toList();
```

---

## 🎯 DEPLOYMENT PASO A PASO

### 1. Abrir Supabase Dashboard
```
https://supabase.com/dashboard/project/[YOUR-PROJECT-ID]/sql/new
```

### 2. Copiar Script SQL v3
Copiar TODO el contenido de:
```
supabase_scripts/2025-11-17_DEPLOY_optimized_tracker_rpcs_v3.sql
```

### 3. Ejecutar en SQL Editor
- Pegar el script completo
- Click en **"Run"** (o Ctrl+Enter)

### 4. Verificar Success Messages
Deberías ver:
```
NOTICE: ✅ SUCCESS: get_order_full_details creada correctamente
NOTICE: ✅ SUCCESS: get_client_active_orders creada correctamente
NOTICE: ========================================
NOTICE: ✅ DEPLOYMENT V3 COMPLETADO EXITOSAMENTE
NOTICE: ========================================
```

### 5. Verificar en la App
1. **Hot Restart** la app Flutter (Dreamflow auto-detecta cambios)
2. Crear una orden de prueba como cliente
3. Verificar que el **mini-tracker** aparece en la parte superior
4. Click en el mini-tracker para ver el **tracker principal**
5. Como restaurante, confirmar la orden
6. Como delivery, aceptar la orden
7. **Verificar que ambos trackers se actualizan automáticamente** sin necesidad de refresh manual

---

## ✅ VALIDACIONES POST-DEPLOYMENT

### Test 1: Mini-Tracker en Home Screen
```
✅ Se muestra cuando hay órdenes activas
✅ Muestra el status correcto de la orden
✅ Muestra el nombre del restaurant
✅ Muestra el nombre del delivery agent (cuando está asignado)
✅ Se actualiza automáticamente cuando cambia el status
```

### Test 2: Tracker Principal (OrderDetailsScreen)
```
✅ Muestra información completa de la orden
✅ Muestra items del pedido con imágenes
✅ Muestra información del restaurant
✅ Muestra información del delivery agent
✅ Se actualiza automáticamente en tiempo real
✅ NO muestra errores de tipo "column does not exist"
```

### Test 3: Tiempo Real
```
✅ Los cambios de status se reflejan INMEDIATAMENTE
✅ Cuando el delivery acepta, su nombre aparece automáticamente
✅ NO es necesario hacer refresh manual
✅ El stream de Supabase está funcionando correctamente
```

---

## 🔍 TROUBLESHOOTING

### Error: "column r.delivery_time does not exist"
**Causa:** Aún estás usando el script v2 (antiguo).
**Solución:** Ejecutar el script v3 que corrige este problema.

### Mini-tracker no se actualiza
**Causa:** El `RealtimeService` no está suscrito correctamente.
**Solución:** Verificar logs en console:
```
🔄 [REALTIME] Obteniendo orden completa via RPC (intento 1/3)...
✅ [REALTIME] Orden completa obtenida exitosamente via RPC en intento 1
✅ [REALTIME] Delivery agent: [NOMBRE DEL DELIVERY]
```

### Tracker principal muestra error
**Causa:** Función RPC devuelve datos incompatibles.
**Solución:** Verificar que el script v3 se ejecutó correctamente y que las funciones tienen la versión correcta.

---

## 📝 NOTAS TÉCNICAS

### Compatibilidad con el Modelo Dart
El modelo `DoaRestaurant.fromJson()` ya maneja correctamente el mapeo:

```dart
// Línea donde se hace el fallback automático
deliveryTime: json['delivery_time'] != null 
    ? json['delivery_time'] as int 
    : json['estimated_delivery_time_minutes'],
```

Esto significa que el RPC puede devolver `estimated_delivery_time_minutes` y el modelo lo mapea automáticamente a `deliveryTime` para la UI. ✅

### Realtime vs Polling
El sistema usa **Realtime de Supabase** como fuente principal:
- `RealtimeService` escucha cambios en la tabla `orders`
- Cuando detecta un cambio, llama al RPC para obtener datos completos
- El stream emite la orden actualizada a todos los widgets suscritos
- **Polling** solo se usa como backup cuando Realtime falla

### Arquitectura del Flujo de Datos
```
┌─────────────────────┐
│   Supabase Table    │
│      (orders)       │
└──────────┬──────────┘
           │ Realtime Event
           ▼
┌─────────────────────┐
│  RealtimeService    │
│  (detecta cambio)   │
└──────────┬──────────┘
           │ Llama RPC
           ▼
┌─────────────────────┐
│  get_order_full_*   │
│  (devuelve JSON)    │
└──────────┬──────────┘
           │ DoaOrder.fromJson()
           ▼
┌─────────────────────┐
│   Stream Emission   │
│ (clientActiveOrders)│
└──────────┬──────────┘
           │
           ├──────────────┬─────────────┐
           ▼              ▼             ▼
    ┌──────────┐  ┌──────────┐  ┌──────────┐
    │   Mini   │  │ Tracker  │  │  Other   │
    │ Tracker  │  │Principal │  │ Widgets  │
    └──────────┘  └──────────┘  └──────────┘
```

---

## 🎉 RESULTADO ESPERADO

Después del deployment v3:

✅ **Mini-tracker funciona perfectamente**
- Se actualiza automáticamente en tiempo real
- Muestra el status correcto
- Muestra el nombre del delivery agent cuando está asignado

✅ **Tracker principal funciona perfectamente**
- Muestra toda la información de la orden
- Se actualiza automáticamente sin errores
- NO hay errores de columnas inexistentes

✅ **Tiempo real 100% funcional**
- Los cambios se reflejan INMEDIATAMENTE
- NO es necesario hacer refresh manual
- La experiencia de usuario es fluida

---

## 📞 CONTACTO

Si encuentras algún problema después del deployment, verifica:
1. Los logs en Dreamflow Debug Console
2. Que el script v3 se ejecutó correctamente en Supabase
3. Que las funciones RPC tienen los permisos correctos (`GRANT EXECUTE`)
