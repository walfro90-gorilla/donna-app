# 📋 INSTRUCCIONES DE DEPLOYMENT - Funciones RPC Optimizadas para Trackers

## 🎯 OBJETIVO
Desplegar funciones RPC optimizadas que permiten a ambos trackers (principal y mini) funcionar correctamente en tiempo real, consumiendo los mismos datos desde Supabase.

---

## 📦 ARCHIVOS INCLUIDOS

1. **2025-11-17_OPTIMIZED_get_order_full_details.sql**
   - Función: `get_order_full_details(order_id_param uuid)`
   - Devuelve: `jsonb` (objeto completo de orden con todos los joins)
   - Uso: Tracker principal y realtime service

2. **2025-11-17_OPTIMIZED_get_client_active_orders.sql**
   - Función: `get_client_active_orders(client_id_param uuid)`
   - Devuelve: `jsonb` (array de órdenes activas completas)
   - Uso: Mini-tracker en home screen

3. **2025-11-17_DEPLOY_optimized_tracker_rpcs.sql**
   - Script de deployment completo con verificación
   - Ejecuta ambas funciones y valida el resultado

---

## 🚀 PASOS PARA DEPLOYMENT

### Opción A: Deployment Automático (Recomendado)

1. **Abrir Supabase SQL Editor**
   - Ir a tu proyecto en Supabase
   - Click en "SQL Editor" en el menú lateral

2. **Ejecutar el script de deployment**
   ```sql
   -- Copiar y pegar el contenido completo de:
   -- 2025-11-17_DEPLOY_optimized_tracker_rpcs.sql
   ```

3. **Verificar los mensajes de éxito**
   ```
   ✅ get_order_full_details desplegada exitosamente
   ✅ get_client_active_orders desplegada exitosamente
   ✅✅✅ [DEPLOY] Todas las funciones desplegadas correctamente
   ```

---

### Opción B: Deployment Manual (Si prefieres control individual)

1. **Desplegar get_order_full_details**
   ```bash
   # Ejecutar en Supabase SQL Editor:
   2025-11-17_OPTIMIZED_get_order_full_details.sql
   ```

2. **Desplegar get_client_active_orders**
   ```bash
   # Ejecutar en Supabase SQL Editor:
   2025-11-17_OPTIMIZED_get_client_active_orders.sql
   ```

---

## ✅ VERIFICACIÓN POST-DEPLOYMENT

### 1. Verificar que las funciones existen

```sql
-- Ejecutar en SQL Editor:
SELECT 
  p.proname as function_name,
  pg_get_function_arguments(p.oid) as arguments,
  pg_get_function_result(p.oid) as return_type
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN ('get_order_full_details', 'get_client_active_orders')
ORDER BY p.proname;
```

**Resultado esperado:**
```
get_order_full_details    | order_id_param uuid | jsonb
get_client_active_orders  | client_id_param uuid | jsonb
```

---

### 2. Probar get_order_full_details con una orden real

```sql
-- Reemplazar 'ORDER_ID_AQUI' con un ID de orden real de tu base de datos
SELECT get_order_full_details('ORDER_ID_AQUI');
```

**Resultado esperado:**
- Un objeto JSON completo con:
  - ✅ Datos de la orden
  - ✅ Restaurant completo (con user)
  - ✅ Delivery agent completo (si existe)
  - ✅ Order items con productos completos

---

### 3. Probar get_client_active_orders con un usuario real

```sql
-- Reemplazar 'USER_ID_AQUI' con un ID de usuario real
SELECT get_client_active_orders('USER_ID_AQUI');
```

**Resultado esperado:**
- Un array JSON de órdenes activas:
  - ✅ Solo órdenes con status activos (no delivered ni canceled)
  - ✅ Cada orden tiene todos los datos completos
  - ✅ Ordenadas por fecha de creación (más reciente primero)

---

## 🔧 TROUBLESHOOTING

### Error: "function does not exist"

**Causa:** La función no se desplegó correctamente

**Solución:**
```sql
-- Verificar que el script se ejecutó sin errores
-- Re-ejecutar el script de deployment completo
```

---

### Error: "column does not exist"

**Causa:** El schema de la base de datos no coincide con el esperado

**Solución:**
```sql
-- Verificar que todas las columnas existen en las tablas:
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'orders'
ORDER BY ordinal_position;

-- Comparar con DATABASE_SCHEMA.sql
```

---

### Error: "permission denied"

**Causa:** Los permisos no se aplicaron correctamente

**Solución:**
```sql
-- Re-aplicar permisos manualmente:
GRANT EXECUTE ON FUNCTION get_order_full_details(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_order_full_details(uuid) TO anon;
GRANT EXECUTE ON FUNCTION get_client_active_orders(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_client_active_orders(uuid) TO anon;
```

---

## 📊 DATOS DE PRUEBA

### Obtener IDs de prueba de tu base de datos

```sql
-- Obtener un order_id de prueba:
SELECT id, status, user_id, restaurant_id, delivery_agent_id 
FROM orders 
WHERE status IN ('pending', 'confirmed', 'in_preparation') 
LIMIT 5;

-- Obtener un user_id con órdenes activas:
SELECT DISTINCT user_id 
FROM orders 
WHERE status IN ('pending', 'confirmed', 'in_preparation', 'ready_for_pickup', 'assigned', 'on_the_way')
LIMIT 5;
```

---

## 🎉 PRÓXIMOS PASOS DESPUÉS DEL DEPLOYMENT

1. **La app Flutter ya está actualizada** para usar estas funciones
2. **No se requieren cambios adicionales** en el código Flutter
3. **Hot restart de la app** para que tome los cambios
4. **Verificar en logs** que aparecen mensajes como:
   ```
   ✅ [TRACKER] X órdenes activas encontradas via RPC
   ✅ [REALTIME] Orden completa obtenida exitosamente via RPC
   ```

---

## 📝 NOTAS IMPORTANTES

- ✅ **Ambas funciones usan `SECURITY DEFINER`** - Se ejecutan con privilegios del propietario
- ✅ **Optimizadas para performance** - Un solo query con todos los JOINs necesarios
- ✅ **Compatibles con DoaOrder.fromJson()** - No se necesita conversión adicional
- ✅ **Incluyen TODOS los datos necesarios** - Restaurant, delivery agent, order items completos
- ✅ **Status activos correctos** - Lista completa de status que no son finales

---

## 🆘 SOPORTE

Si encuentras algún error durante el deployment:

1. **Copia el mensaje de error completo**
2. **Verifica que estás usando Supabase SQL Editor** (no psql o terminal)
3. **Asegúrate de tener permisos de administrador** en el proyecto
4. **Revisa los logs de la función** en Supabase Dashboard > Database > Functions

---

## 📅 FECHA DE CREACIÓN
2025-11-17

## 👨‍💻 AUTOR
Hologram - Dreamflow Assistant

## 🔗 ARCHIVOS RELACIONADOS
- `/lib/services/realtime_service.dart` - Consume las funciones RPC
- `/lib/screens/orders/order_details_screen.dart` - Usa get_order_full_details
- `/lib/widgets/multi_order_tracker.dart` - Consume el stream de órdenes activas
- `/lib/widgets/active_order_tracker.dart` - Muestra los datos de las órdenes
