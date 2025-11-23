# 🔧 PLAN PROFESIONAL: REPARACIÓN DEFINITIVA DEL ORDER TRACKER

**Fecha:** 2025-11-16  
**Autor:** Hologram  
**Objetivo:** Hacer que ambos trackers (principal y mini) funcionen en tiempo real usando el mismo flujo de datos de Supabase Realtime

---

## 📊 DIAGNÓSTICO ACTUAL

### ✅ **LO QUE FUNCIONA:**
1. **Mini-tracker en home_screen.dart:**
   - ✅ Consume el stream `RealtimeNotificationService().clientActiveOrders`
   - ✅ Recibe actualizaciones en tiempo real vía WebSocket
   - ✅ Muestra cambios de status y delivery agent correctamente
   - ✅ Se actualiza automáticamente sin refresh manual

2. **Función RPC `get_client_active_orders`:**
   - ✅ Devuelve todas las órdenes activas del cliente
   - ✅ Incluye LEFT JOIN con `users` para obtener nombre y teléfono del delivery agent
   - ✅ Funciona correctamente cuando se consume vía `RealtimeService`

### ❌ **LO QUE FALLA:**

1. **Tracker principal en order_details_screen.dart:**
   - ❌ Llama directamente a RPC `get_order_with_details` 
   - ❌ Error al convertir respuesta: `TypeError: Instance of 'minified:J<dynamic>' is not a subtype of type 'Map<dynamic, dynamic>'`
   - ❌ No muestra información del restaurante: "Restaurante no disponible"
   - ❌ No muestra información del delivery agent correctamente
   - ❌ No se actualiza automáticamente en tiempo real

2. **Console logs reveladores:**
   ```
   🔍 [ORDER_DETAILS] Response type: minified:J<dynamic>
   ❌ [ORDER_DETAILS] Error actualizando pedido: TypeError: Instance of 'minified:J<dynamic>': 
      type 'minified:J<dynamic>' is not a subtype of type 'Map<dynamic, dynamic>'
   ```

---

## 🎯 SOLUCIÓN PROPUESTA

### **ESTRATEGIA: UNIFICAR AMBOS TRACKERS BAJO EL MISMO FLUJO DE REALTIME**

**Principio:** Si el mini-tracker funciona perfectamente con el stream de realtime, el tracker principal debe usar **exactamente el mismo flujo**.

### **CAMBIOS REQUERIDOS:**

#### 1️⃣ **ELIMINAR llamadas directas a RPC en order_details_screen.dart**
   - ❌ Remover: `SupabaseConfig.client.rpc('get_order_with_details', ...)`
   - ✅ Usar: Stream de `RealtimeNotificationService().orderUpdates`

#### 2️⃣ **SUSCRIBIR order_details_screen.dart al stream de realtime**
   - Escuchar actualizaciones de la orden específica via `orderUpdates` stream
   - Actualizar el estado automáticamente cuando llegan eventos de realtime
   - Mantener sincronización perfecta con el mini-tracker

#### 3️⃣ **CREAR nueva función RPC: `get_order_full_details`** (OPCIONAL - solo si necesitamos más info)
   - Esta función traerá **TODA** la información necesaria:
     - ✅ Datos de la orden (de `orders`)
     - ✅ Información del restaurante (de `restaurants` + `users`)
     - ✅ Información del delivery agent (de `users`)
     - ✅ Items de la orden (de `order_items` + `products`)
   - Se usará **SOLO** para carga inicial, no para updates en tiempo real

#### 4️⃣ **VERIFICAR DoaOrder.fromJson()** maneja correctamente los campos del RPC
   - Debe parsear correctamente `delivery_user_name` y `delivery_user_phone`
   - Debe crear objeto `DeliveryAgent` con estos datos
   - Debe manejar correctamente restaurante y sus datos

---

## 📋 IMPLEMENTACIÓN PASO A PASO

### **FASE 1: CREAR NUEVA FUNCIÓN RPC COMPLETA (si es necesaria)**

```sql
-- Archivo: supabase_scripts/2025-11-16_CREATE_rpc_get_order_full_details.sql

CREATE OR REPLACE FUNCTION get_order_full_details(order_id_param uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result jsonb;
BEGIN
  -- Construir JSON completo con toda la información
  SELECT jsonb_build_object(
    'id', o.id,
    'user_id', o.user_id,
    'restaurant_id', o.restaurant_id,
    'delivery_agent_id', o.delivery_agent_id,
    'status', o.status,
    'total_amount', o.total_amount,
    'delivery_fee', o.delivery_fee,
    'payment_method', o.payment_method,
    'delivery_address', o.delivery_address,
    'delivery_latlng', o.delivery_latlng,
    'delivery_lat', o.delivery_lat,
    'delivery_lon', o.delivery_lon,
    'delivery_place_id', o.delivery_place_id,
    'delivery_address_structured', o.delivery_address_structured,
    'pickup_code', o.pickup_code,
    'confirm_code', o.confirm_code,
    'order_notes', o.order_notes,
    'assigned_at', o.assigned_at,
    'delivery_time', o.delivery_time,
    'pickup_time', o.pickup_time,
    'created_at', o.created_at,
    'updated_at', o.updated_at,
    
    -- Restaurante completo
    'restaurant', jsonb_build_object(
      'id', r.id,
      'name', r.name,
      'description', r.description,
      'logo_url', r.logo_url,
      'address', r.address,
      'phone', ru.phone,
      'location_lat', r.location_lat,
      'location_lon', r.location_lon,
      'estimated_delivery_time_minutes', r.estimated_delivery_time_minutes,
      'delivery_radius_km', r.delivery_radius_km
    ),
    
    -- Delivery agent completo
    'delivery_agent', CASE 
      WHEN o.delivery_agent_id IS NOT NULL THEN
        jsonb_build_object(
          'id', du.id,
          'name', du.name,
          'phone', du.phone,
          'email', du.email
        )
      ELSE NULL
    END,
    
    -- Items de la orden
    'order_items', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', oi.id,
          'quantity', oi.quantity,
          'price_at_time_of_order', oi.price_at_time_of_order,
          'product', jsonb_build_object(
            'id', p.id,
            'name', p.name,
            'description', p.description,
            'price', p.price,
            'image_url', p.image_url
          )
        )
      )
      FROM order_items oi
      LEFT JOIN products p ON p.id = oi.product_id
      WHERE oi.order_id = o.id
    )
  ) INTO result
  FROM orders o
  LEFT JOIN restaurants r ON r.id = o.restaurant_id
  LEFT JOIN users ru ON ru.id = r.user_id
  LEFT JOIN users du ON du.id = o.delivery_agent_id
  WHERE o.id = order_id_param;
  
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_order_full_details(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_order_full_details(uuid) TO anon;
```

**Test Query:**
```sql
SELECT * FROM get_order_full_details('32731162-6a1a-4e68-9b76-1e1f5eb4e3e0');
```

---

### **FASE 2: REFACTORIZAR order_details_screen.dart**

**Cambios:**
1. ✅ Remover `_refreshOrderDetails()` que llama al RPC directamente
2. ✅ Suscribirse a `RealtimeNotificationService().orderUpdates`
3. ✅ Usar `get_order_full_details` **SOLO** para carga inicial
4. ✅ Todas las actualizaciones posteriores vienen del stream de realtime

```dart
// Pseudo-código de la nueva implementación

@override
void initState() {
  super.initState();
  _order = widget.order;
  
  // 1. Cargar datos iniciales completos (una sola vez)
  _loadInitialOrderDetails();
  
  // 2. Suscribirse al stream de realtime para updates automáticos
  _subscribeToRealtimeUpdates();
  
  _checkIfAlreadyReviewed();
}

Future<void> _loadInitialOrderDetails() async {
  try {
    final response = await SupabaseConfig.client
        .rpc('get_order_full_details', params: {'order_id_param': _order.id});
    
    if (response != null) {
      final jsonData = response as Map<String, dynamic>;
      final updatedOrder = DoaOrder.fromJson(jsonData);
      
      if (mounted) {
        setState(() {
          _order = updatedOrder;
        });
      }
    }
  } catch (e) {
    debugPrint('❌ [ORDER_DETAILS] Error cargando orden: $e');
  }
}

void _subscribeToRealtimeUpdates() {
  final rt = RealtimeNotificationService();
  
  // Suscribirse a actualizaciones de ESTA orden específica
  _orderUpdatesSub = rt.orderUpdates.listen((updatedOrder) {
    if (!mounted) return;
    
    if (updatedOrder.id == _order.id) {
      debugPrint('📡 [ORDER_DETAILS] Actualización realtime recibida');
      setState(() {
        _order = updatedOrder;
      });
    }
  });
}
```

---

### **FASE 3: VERIFICAR DoaOrder.fromJson()**

Asegurarse que el modelo `DoaOrder` maneja correctamente:

```dart
factory DoaOrder.fromJson(Map<String, dynamic> json) {
  return DoaOrder(
    // ... campos básicos ...
    
    // ✅ CRÍTICO: Parsear delivery agent correctamente
    deliveryAgent: json['delivery_agent'] != null 
        ? DeliveryAgent.fromJson(json['delivery_agent'] as Map<String, dynamic>)
        : (json['delivery_user_name'] != null 
            ? DeliveryAgent(
                id: json['delivery_agent_id'] as String?,
                name: json['delivery_user_name'] as String?,
                phone: json['delivery_user_phone'] as String?,
              )
            : null),
    
    // ✅ CRÍTICO: Parsear restaurante correctamente
    restaurant: json['restaurant'] != null
        ? Restaurant.fromJson(json['restaurant'] as Map<String, dynamic>)
        : null,
    
    // ✅ CRÍTICO: Parsear order items correctamente
    orderItems: (json['order_items'] as List?)
        ?.map((item) => OrderItem.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}
```

---

## ✅ CHECKLIST DE VALIDACIÓN

### **Tests a realizar ANTES de completar:**

- [ ] **Test 1:** Verificar que el RPC `get_order_full_details` devuelve JSON completo
  ```sql
  SELECT * FROM get_order_full_details('order-id-aqui');
  ```

- [ ] **Test 2:** Verificar que el tracker principal carga correctamente la primera vez

- [ ] **Test 3:** Cambiar status de orden desde admin y verificar que el tracker principal se actualiza automáticamente

- [ ] **Test 4:** Asignar repartidor a orden y verificar que aparece en tracker principal automáticamente

- [ ] **Test 5:** Verificar que NO aparece el error `TypeError: Instance of 'minified:J<dynamic>'`

- [ ] **Test 6:** Verificar que mini-tracker y tracker principal muestran la misma información en tiempo real

---

## 🎯 RESULTADO ESPERADO

✅ **Tracker Principal:**
- Carga completa en primera apertura
- Se actualiza automáticamente vía realtime
- Muestra restaurante correctamente
- Muestra delivery agent correctamente  
- Muestra productos correctamente
- Sin errores de tipo en console

✅ **Mini-Tracker:**
- Sigue funcionando como antes
- Sincronizado con tracker principal

✅ **Ambos:**
- Usan el mismo flujo de datos (Realtime WebSocket)
- Actualizaciones instantáneas sin polling
- Sin llamadas RPC repetitivas
- Experiencia fluida para el usuario

---

## 📝 PREGUNTAS PARA EL USUARIO

1. ¿Prefieres que creemos la nueva función RPC `get_order_full_details` o usamos `get_order_with_details` existente?

2. ¿Necesitas que el tracker principal muestre información adicional que no está en el mini-tracker?

3. ¿Está bien remover el botón de refresh manual si todo se actualiza automáticamente?

---

## 🚀 SIGUIENTE PASO

Una vez aprobado el plan, procederé a:
1. Crear el archivo SQL con la nueva función RPC (si es necesaria)
2. Refactorizar `order_details_screen.dart` para usar el stream de realtime
3. Verificar que `DoaOrder.fromJson()` maneja todos los campos correctamente
4. Ejecutar todos los tests del checklist
5. Confirmar que ambos trackers funcionan perfectamente

---

**¿Aprobamos este plan y procedemos con la implementación?** 🎯
