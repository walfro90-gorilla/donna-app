# 📱 PLAN DE IMPLEMENTACIÓN - SISTEMA "NOT DELIVERED" EN LA APP

## ✅ SQL COMPLETADO
- ✅ Archivo: `sql_migrations/2025-01-16_not_delivered_system_FINAL.sql`
- ✅ Listo para ejecutar en Supabase

---

## 🎯 CAMBIOS NECESARIOS EN LA APP FLUTTER

### **1. MODELOS DE DATOS** (`lib/models/doa_models.dart`)

#### **1.1 Agregar nuevo OrderStatus: `notDelivered`**
```dart
enum OrderStatus {
  pending,
  confirmed,
  inPreparation,
  readyForPickup,
  assigned,
  onTheWay,
  delivered,
  canceled,
  notDelivered,  // NUEVO ✨
}

// Actualizar fromString:
case 'not_delivered':
  return OrderStatus.notDelivered;

// Actualizar toBackendString:
case OrderStatus.notDelivered:
  return 'not_delivered';
```

#### **1.2 Crear clase `ClientDebt`**
```dart
class ClientDebt {
  final String id;
  final String clientId;
  final String orderId;
  final double amount;
  final String reason; // 'not_delivered', 'client_no_show', 'fake_address', 'other'
  final String status; // 'pending', 'paid', 'forgiven', 'disputed'
  final String? photoUrl;
  final String? deliveryNotes;
  
  // Disputa
  final String? disputeReason;
  final String? disputePhotoUrl;
  final DateTime? disputeCreatedAt;
  final DateTime? disputeResolvedAt;
  final String? disputeResolvedBy;
  final String? disputeResolutionNotes;
  
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? paidAt;
  final DateTime? forgivenAt;
  final String? forgivenBy;
  
  // Constructor, fromJson, toJson, copyWith
}
```

#### **1.3 Crear clase `ClientAccountSuspension`**
```dart
class ClientAccountSuspension {
  final String id;
  final String clientId;
  final int failedAttempts;
  final bool isSuspended;
  final DateTime? suspendedAt;
  final DateTime? suspensionExpiresAt;
  final String? lastFailedOrderId;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Constructor, fromJson, toJson, copyWith
}
```

---

### **2. SERVICIOS**

#### **2.1 Crear `lib/services/debt_service.dart`**
Servicio para manejar deudas de clientes:

```dart
class DebtService {
  // 1. Obtener deudas del cliente
  static Future<List<ClientDebt>> getClientDebts(String clientId)
  
  // 2. Verificar suspensión de cuenta
  static Future<Map<String, dynamic>> checkClientSuspension(String clientId)
  
  // 3. Disputar una deuda
  static Future<Map<String, dynamic>> disputeDebt({
    required String debtId,
    required String clientId,
    required String disputeReason,
    String? disputePhotoUrl,
  })
  
  // 4. Perdonar deuda (admin)
  static Future<Map<String, dynamic>> forgiveDebt({
    required String debtId,
    required String adminId,
    String? notes,
  })
  
  // 5. Resolver disputa (admin)
  static Future<Map<String, dynamic>> resolveDispute({
    required String debtId,
    required String adminId,
    required String resolution, // 'forgive' o 'uphold'
    String? resolutionNotes,
  })
}
```

#### **2.2 Actualizar `lib/core/services/delivery_service.dart`**
Agregar función para marcar orden como no entregada:

```dart
class DeliveryService {
  // Nueva función
  Future<Map<String, dynamic>> markOrderNotDelivered({
    required String orderId,
    required String deliveryAgentId,
    String? photoUrl,
    String? deliveryNotes,
    String reason = 'not_delivered',
  }) async {
    try {
      final response = await SupabaseConfig.client.rpc(
        'mark_order_not_delivered',
        params: {
          'p_order_id': orderId,
          'p_delivery_agent_id': deliveryAgentId,
          'p_photo_url': photoUrl,
          'p_delivery_notes': deliveryNotes,
          'p_reason': reason,
        },
      );
      
      // Emitir evento de orden actualizada
      emit(OrderStatusChangedEvent(
        orderId: orderId,
        newStatus: 'not_delivered',
      ));
      
      return response;
    } catch (e) {
      print('❌ Error marking order as not delivered: $e');
      rethrow;
    }
  }
}
```

---

### **3. PANTALLAS Y UI**

#### **3.1 Actualizar `delivery_order_detail_screen.dart`**

**Cambios necesarios:**
1. Agregar botón "No Entregada" en la pantalla de detalle de orden
2. Mostrar modal para capturar:
   - Razón (dropdown: client_no_show, fake_address, other)
   - Foto de evidencia (opcional pero recomendado)
   - Notas del repartidor
3. Tiempo de espera: 5-10 minutos antes de poder marcar como no entregada
4. Después de marcar, mostrar modal de review (como con delivered)

**Ubicación del botón:**
- Solo visible cuando status = 'on_the_way' o 'in_transit'
- Junto al botón "Marcar como Entregada"

#### **3.2 Crear `lib/screens/client/my_debts_screen.dart`**
Pantalla para que el cliente vea sus deudas:
- Lista de deudas pendientes
- Botón para disputar cada deuda
- Estado de disputas
- Total adeudado

#### **3.3 Crear `lib/screens/admin/debts_management_screen.dart`**
Pantalla para admin:
- Ver todas las deudas
- Filtrar por status (pending, disputed, forgiven, paid)
- Ver evidencias (fotos del repartidor y cliente)
- Resolver disputas
- Perdonar deudas

---

### **4. WIDGETS PERSONALIZADOS**

#### **4.1 Crear `lib/widgets/not_delivered_modal.dart`**
Modal para capturar información cuando se marca como no entregada:

```dart
class NotDeliveredModal extends StatefulWidget {
  final String orderId;
  final Function(Map<String, dynamic> result) onSubmit;
}
```

**Campos:**
- Dropdown de razones
- Campo de notas
- Widget de captura de foto (usa `image_upload_field.dart` existente)
- Botón "Confirmar No Entrega"

#### **4.2 Crear `lib/widgets/debt_card.dart`**
Card para mostrar deudas en la lista:
- Monto
- Razón
- Fecha
- Botón "Disputar" o "Ver Disputa"
- Estado visual

---

### **5. VALIDACIONES Y LÓGICA DE NEGOCIO**

#### **5.1 Checkout: Verificar suspensión antes de crear orden**
En `checkout_screen.dart`:

```dart
// Antes de crear la orden
final suspensionCheck = await DebtService.checkClientSuspension(clientId);

if (suspensionCheck['is_suspended'] == true) {
  // Mostrar mensaje de error
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Cuenta Suspendida'),
      content: Text('Tu cuenta está temporalmente suspendida por órdenes no entregadas. '
                    'Expira en: ${suspensionCheck['suspension_expires_at']}'),
    ),
  );
  return;
}

if (suspensionCheck['pending_debts'] > 0) {
  // Mostrar mensaje de deuda pendiente
  showDialog(...);
  return;
}
```

#### **5.2 Home: Mostrar banner de deudas pendientes**
En `home_screen.dart`, agregar widget de alerta al inicio si hay deudas:

```dart
FutureBuilder<List<ClientDebt>>(
  future: DebtService.getClientDebts(userId),
  builder: (context, snapshot) {
    if (snapshot.hasData && snapshot.data!.isNotEmpty) {
      final pendingDebts = snapshot.data!
        .where((d) => d.status == 'pending')
        .toList();
      
      if (pendingDebts.isNotEmpty) {
        return DebtWarningBanner(debts: pendingDebts);
      }
    }
    return SizedBox.shrink();
  },
)
```

---

### **6. NOTIFICACIONES**

#### **6.1 Agregar notificación al crear deuda**
Cuando se marca como "not_delivered":
- Push notification al cliente
- Email si es posible
- Mensaje en la app

Contenido:
```
"⚠️ Orden no entregada"
"Tu orden #123 no pudo ser entregada. Por favor revisa los detalles y disputa si crees que es un error."
```

#### **6.2 Notificación de suspensión**
Cuando se llega a 3 intentos fallidos:
```
"⛔ Cuenta Suspendida Temporalmente"
"Tu cuenta ha sido suspendida por 10 minutos debido a órdenes no entregadas. Expira a las XX:XX"
```

---

### **7. ORDEN DE IMPLEMENTACIÓN RECOMENDADO**

#### **Fase 1: Modelos y Servicios (Backend)**
1. ✅ SQL script (ya creado)
2. Agregar `notDelivered` a `OrderStatus` enum
3. Crear modelos: `ClientDebt`, `ClientAccountSuspension`
4. Crear `DebtService`
5. Actualizar `DeliveryService.markOrderNotDelivered()`

#### **Fase 2: UI para Repartidor**
6. Crear `NotDeliveredModal` widget
7. Actualizar `delivery_order_detail_screen.dart`:
   - Agregar botón "No Entregada"
   - Integrar modal
   - Captura de foto de evidencia
   - Mostrar review después de marcar

#### **Fase 3: UI para Cliente**
8. Crear `DebtCard` widget
9. Crear `my_debts_screen.dart`
10. Agregar banner de deudas en `home_screen.dart`
11. Agregar validación en `checkout_screen.dart`

#### **Fase 4: UI para Admin**
12. Crear `debts_management_screen.dart`
13. Agregar opción en `admin_main_dashboard.dart`
14. Vista de disputas con evidencias

#### **Fase 5: Notificaciones y Pulido**
15. Implementar notificaciones push
16. Testing completo
17. Ajustes de UX

---

### **8. ARCHIVOS A CREAR**

#### **Nuevos archivos:**
```
lib/
├── models/
│   └── (actualizar doa_models.dart)
├── services/
│   └── debt_service.dart  ✨ NUEVO
├── screens/
│   ├── client/
│   │   └── my_debts_screen.dart  ✨ NUEVO
│   └── admin/
│       └── debts_management_screen.dart  ✨ NUEVO
└── widgets/
    ├── not_delivered_modal.dart  ✨ NUEVO
    ├── debt_card.dart  ✨ NUEVO
    └── debt_warning_banner.dart  ✨ NUEVO
```

#### **Archivos a modificar:**
```
lib/
├── models/doa_models.dart  (agregar enums y clases)
├── core/services/delivery_service.dart  (agregar markOrderNotDelivered)
├── screens/
│   ├── delivery/delivery_order_detail_screen.dart  (agregar botón y modal)
│   ├── checkout/checkout_screen.dart  (agregar validación)
│   ├── home/home_screen.dart  (agregar banner de deudas)
│   └── admin/admin_main_dashboard.dart  (agregar opción de deudas)
└── core/utils/order_status_helper.dart  (actualizar helpers para not_delivered)
```

---

### **9. CHECKLIST DE TESTING**

#### **Testing de Repartidor:**
- [ ] Puede marcar orden como "No Entregada"
- [ ] Puede subir foto de evidencia
- [ ] Puede agregar notas
- [ ] Aparece modal de review después
- [ ] Orden cambia a status "not_delivered"

#### **Testing de Cliente:**
- [ ] Ve banner de deuda pendiente
- [ ] Puede ver detalles de la deuda
- [ ] Puede disputar con foto
- [ ] No puede crear orden si tiene deuda pendiente
- [ ] Cuenta se suspende después de 3 intentos
- [ ] Suspensión expira después de 10 minutos

#### **Testing de Admin:**
- [ ] Ve todas las deudas
- [ ] Puede ver evidencias (fotos)
- [ ] Puede resolver disputas
- [ ] Puede perdonar deudas
- [ ] Contador de intentos se resetea al perdonar

#### **Testing Financiero:**
- [ ] Transacciones se crean correctamente
- [ ] Restaurante recibe su pago
- [ ] Repartidor recibe su pago
- [ ] Balance 0 se mantiene
- [ ] Cliente queda con deuda registrada

---

## 🚀 SIGUIENTE PASO

1. **Ejecutar SQL en Supabase** (instrucciones arriba)
2. **Confirmar que quieres que implemente los cambios en Flutter**
3. **Empezar con Fase 1: Modelos y Servicios**

¿Procedo con la implementación Flutter? 🎯
