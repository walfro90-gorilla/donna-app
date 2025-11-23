# 🎯 REFACTORIZACIÓN SUPABASE - RESUMEN FINAL

## ✅ ESTADO ACTUAL

Has completado exitosamente los scripts del **1 al 7**. Te faltaban ejecutar los scripts **8, 9, 10 y 11**.

Durante el proceso encontraste varios errores debido a:
1. ❌ Funciones con nombres ambiguos (múltiples overloads)
2. ❌ Políticas RLS duplicadas
3. ❌ Referencias a tablas incorrectas (`clients` y `delivery_agents` que no existen)
4. ❌ Roles incorrectos (`'client'` en lugar de `'cliente'`)

---

## 🔧 SOLUCIÓN IMPLEMENTADA

He creado **scripts corregidos** basados en tu `DATABASE_SCHEMA.sql` real:

### **📁 SCRIPTS NUEVOS CORREGIDOS (USAR ESTOS):**

| Script | Descripción | Estado |
|--------|-------------|--------|
| `09_cleanup_all_policies.sql` | ✅ Limpia todas las políticas RLS | **EJECUTAR PRIMERO** |
| `NUEVO_08_create_register_rpcs_v2_CORREGIDO.sql` | ✅ Crea funciones de registro corregidas | **EJECUTAR SEGUNDO** |
| `NUEVO_09_update_rls_policies_v3_CORREGIDO.sql` | ✅ Crea políticas RLS correctas | **EJECUTAR TERCERO** |
| `NUEVO_11_create_indexes_OPTIMIZADO.sql` | ✅ Crea índices optimizados | **EJECUTAR CUARTO** |
| `NUEVO_12_create_auto_registration_trigger.sql` | ⚠️ Trigger opcional de auto-registro | **OPCIONAL** |
| `NUEVO_10_test_registrations_CORREGIDO.sql` | 🔍 Script de verificación | **EJECUTAR AL FINAL** |

---

## 📋 ORDEN DE EJECUCIÓN FINAL

### **✅ PASO 1: Limpiar políticas RLS**
```bash
Script: supabase_scripts/refactor_2025/09_cleanup_all_policies.sql
```
- Elimina TODAS las políticas RLS existentes
- Evita conflictos de "policy already exists"

---

### **✅ PASO 2: Crear funciones de registro**
```bash
Script: supabase_scripts/refactor_2025/NUEVO_08_create_register_rpcs_v2_CORREGIDO.sql
```

**Funciones creadas:**
1. ✅ `register_client(email, password, name, phone, address, lat, lon, address_structured)`
2. ✅ `register_restaurant(email, password, restaurant_name, contact_name, phone, address, lat, lon, address_structured)`
3. ✅ `register_delivery_agent(email, password, name, phone, vehicle_type)`

**Qué hacen:**
- ✅ Insertan/actualizan en `public.users` con el rol correcto (`'cliente'`, `'restaurante'`, `'repartidor'`)
- ✅ Insertan/actualizan en tablas de perfil (`client_profiles`, `restaurants`, `delivery_agent_profiles`)
- ✅ Crean preferencias de usuario (`user_preferences`)
- ✅ Crean cuentas financieras (`accounts`) para restaurantes y repartidores
- ✅ Crean notificaciones de admin (`admin_notifications`) para registros de restaurantes y repartidores

---

### **✅ PASO 3: Crear políticas RLS**
```bash
Script: supabase_scripts/refactor_2025/NUEVO_09_update_rls_policies_v3_CORREGIDO.sql
```

**Políticas creadas para:**
- ✅ `public.users` (usuarios pueden ver/editar su propio registro)
- ✅ `public.client_profiles` (clientes pueden ver/editar su propio perfil)
- ✅ `public.restaurants` (restaurantes pueden ver/editar su propio perfil; público puede ver aprobados)
- ✅ `public.delivery_agent_profiles` (repartidores pueden ver/editar su propio perfil)
- ✅ `public.user_preferences` (usuarios pueden ver/editar sus propias preferencias)
- ✅ `public.accounts` (usuarios pueden ver/editar sus propias cuentas)
- ✅ Admins pueden ver/editar todo

---

### **✅ PASO 4: Crear índices optimizados**
```bash
Script: supabase_scripts/refactor_2025/NUEVO_11_create_indexes_OPTIMIZADO.sql
```

**Índices creados para:**
- ✅ Búsquedas por email, role, phone en `users`
- ✅ Búsquedas por ubicación en `client_profiles`, `restaurants`, `orders`
- ✅ Búsquedas por status en `restaurants`, `delivery_agent_profiles`, `orders`
- ✅ Queries del dashboard de restaurante/repartidor
- ✅ Queries de transacciones financieras

---

### **⚠️ PASO 5: (OPCIONAL) Crear trigger de auto-registro**
```bash
Script: supabase_scripts/refactor_2025/NUEVO_12_create_auto_registration_trigger.sql
```

**⚠️ USAR SOLO SI:**
- Quieres que `auth.users` → `public.users` se sincronice automáticamente
- No necesitas capturar datos específicos durante el registro
- Todos los usuarios empiezan como `'cliente'` y luego cambian de rol

**❌ NO USAR SI:**
- Necesitas capturar datos específicos durante el registro (dirección, teléfono, etc.)
- Quieres control total del flujo de registro

**💡 RECOMENDACIÓN:** NO usar este trigger. Es mejor llamar manualmente a `register_client()`, `register_restaurant()` o `register_delivery_agent()` desde Flutter.

---

### **🔍 PASO 6: Verificar todo**
```bash
Script: supabase_scripts/refactor_2025/NUEVO_10_test_registrations_CORREGIDO.sql
```

**Qué verifica:**
- ✅ Funciones de registro existen y tienen la firma correcta
- ✅ Tablas necesarias existen
- ✅ Columnas críticas existen
- ✅ Foreign keys están correctas
- 📋 Muestra instrucciones de cómo probar desde Flutter

---

## 🚀 INTEGRACIÓN CON FLUTTER

### **📱 Ejemplo 1: Registro de Cliente**
```dart
// Paso 1: SignUp en auth.users
final authResponse = await supabase.auth.signUp(
  email: 'cliente@example.com',
  password: 'password123',
);

if (authResponse.user != null) {
  // Paso 2: Completar perfil llamando a register_client
  final result = await supabase.rpc('register_client', params: {
    'p_email': 'cliente@example.com',
    'p_password': 'password123',
    'p_name': 'Juan Pérez',
    'p_phone': '+52 55 1234 5678',
    'p_address': 'Calle Principal 123, Col. Centro, CDMX',
    'p_lat': 19.4326,
    'p_lon': -99.1332,
    'p_address_structured': {
      'street': 'Calle Principal',
      'number': '123',
      'neighborhood': 'Centro',
      'city': 'Ciudad de México',
      'state': 'CDMX',
      'country': 'México',
      'postal_code': '01000'
    }
  });
  
  print('✅ Cliente registrado: $result');
  // Resultado: {success: true, user_id: "uuid", role: "cliente", message: "..."}
}
```

### **📱 Ejemplo 2: Registro de Restaurante**
```dart
// Paso 1: SignUp en auth.users
final authResponse = await supabase.auth.signUp(
  email: 'restaurante@example.com',
  password: 'password123',
);

if (authResponse.user != null) {
  // Paso 2: Completar perfil llamando a register_restaurant
  final result = await supabase.rpc('register_restaurant', params: {
    'p_email': 'restaurante@example.com',
    'p_password': 'password123',
    'p_restaurant_name': 'Tacos El Güero',
    'p_contact_name': 'María González',
    'p_phone': '+52 55 9876 5432',
    'p_address': 'Avenida Reforma 456, Col. Juárez, CDMX',
    'p_location_lat': 19.4330,
    'p_location_lon': -99.1350,
    'p_address_structured': {
      'street': 'Avenida Reforma',
      'number': '456',
      'neighborhood': 'Juárez',
      'city': 'Ciudad de México',
      'state': 'CDMX',
      'country': 'México',
      'postal_code': '06600'
    }
  });
  
  print('✅ Restaurante registrado: $result');
  // Resultado: {success: true, user_id: "uuid", restaurant_id: "uuid", role: "restaurante", message: "..."}
  
  // IMPORTANTE: El restaurante inicia con status='pending' y requiere aprobación de admin
}
```

### **📱 Ejemplo 3: Registro de Repartidor**
```dart
// Paso 1: SignUp en auth.users
final authResponse = await supabase.auth.signUp(
  email: 'repartidor@example.com',
  password: 'password123',
);

if (authResponse.user != null) {
  // Paso 2: Completar perfil llamando a register_delivery_agent
  final result = await supabase.rpc('register_delivery_agent', params: {
    'p_email': 'repartidor@example.com',
    'p_password': 'password123',
    'p_name': 'Carlos Ramírez',
    'p_phone': '+52 55 5555 5555',
    'p_vehicle_type': 'motocicleta'
  });
  
  print('✅ Repartidor registrado: $result');
  // Resultado: {success: true, user_id: "uuid", role: "repartidor", message: "..."}
  
  // IMPORTANTE: El repartidor inicia con status='pending' y account_state='pending'
  // Requiere completar onboarding y aprobación de admin
}
```

---

## 📊 DIFERENCIAS CON SCRIPTS ANTERIORES

### **❌ Scripts ANTIGUOS (NO USAR):**
- `06_create_register_client.sql`
- `07_create_register_restaurant.sql`
- `08_create_register_delivery_agent.sql`
- `08_create_register_rpcs.sql`
- `09_update_rls_policies.sql`
- `09_update_rls_policies_v2.sql`
- `10_test_registrations.sql`
- `10_test_registrations_fixed.sql`
- `10_test_registrations_fixed_v2.sql`
- `10_test_registrations_fixed_v3.sql`
- `10_test_registrations_v4.sql`
- `11_create_indexes.sql`

### **✅ Scripts NUEVOS CORREGIDOS (USAR ESTOS):**
- `09_cleanup_all_policies.sql` ✅
- `NUEVO_08_create_register_rpcs_v2_CORREGIDO.sql` ✅
- `NUEVO_09_update_rls_policies_v3_CORREGIDO.sql` ✅
- `NUEVO_11_create_indexes_OPTIMIZADO.sql` ✅
- `NUEVO_12_create_auto_registration_trigger.sql` ⚠️ (opcional)
- `NUEVO_10_test_registrations_CORREGIDO.sql` 🔍

---

## 🔍 QUÉ SE CORRIGIÓ

### **1️⃣ Tablas incorrectas:**
- ❌ **Antes:** `clients`, `delivery_agents`
- ✅ **Ahora:** `client_profiles`, `delivery_agent_profiles`

### **2️⃣ Roles incorrectos:**
- ❌ **Antes:** `'client'`, `'restaurant'`, `'delivery_agent'`
- ✅ **Ahora:** `'cliente'`, `'restaurante'`, `'repartidor'`

### **3️⃣ Campos faltantes:**
- ✅ Ahora se crean automáticamente:
  - `user_preferences` (para onboarding y configuraciones)
  - `accounts` (para transacciones financieras)
  - `admin_notifications` (para notificar nuevos registros)

### **4️⃣ Foreign keys:**
- ✅ Ahora se respeta la constraint correcta de `restaurants(user_id)` → `users(id)`

### **5️⃣ Políticas RLS:**
- ✅ Ahora usan las tablas correctas
- ✅ Admins pueden ver/editar todo
- ✅ Usuarios regulares solo ven/editan su propio contenido
- ✅ Restaurantes aprobados son visibles públicamente

---

## ⚠️ NOTAS IMPORTANTES

### **🔒 Seguridad:**
- ✅ Todas las funciones son `SECURITY DEFINER`
- ✅ Todas validan `auth.uid()` antes de ejecutar
- ✅ RLS habilitado en todas las tablas sensibles
- ✅ Usuarios solo pueden modificar sus propios datos

### **💰 Finanzas:**
- ✅ Se crean automáticamente cuentas (`accounts`) para restaurantes y repartidores
- ✅ Balance inicial: `0.00`
- ✅ Account types: `'restaurant'`, `'delivery_agent'`

### **🔔 Notificaciones:**
- ✅ Cada registro de restaurante o repartidor crea una notificación para admins
- ✅ Los admins pueden revisar/aprobar desde el panel de administración

### **📝 Preferencias:**
- ✅ Se crean automáticamente `user_preferences` para todos los usuarios
- ✅ Útil para tracking de onboarding, primera sesión, etc.

---

## ✅ CHECKLIST FINAL

- [ ] **PASO 1:** Ejecutar `09_cleanup_all_policies.sql`
- [ ] **PASO 2:** Ejecutar `NUEVO_08_create_register_rpcs_v2_CORREGIDO.sql`
- [ ] **PASO 3:** Ejecutar `NUEVO_09_update_rls_policies_v3_CORREGIDO.sql`
- [ ] **PASO 4:** Ejecutar `NUEVO_11_create_indexes_OPTIMIZADO.sql`
- [ ] **PASO 5 (Opcional):** Ejecutar `NUEVO_12_create_auto_registration_trigger.sql`
- [ ] **PASO 6:** Ejecutar `NUEVO_10_test_registrations_CORREGIDO.sql` (verificación)
- [ ] **PASO 7:** Probar registro desde Flutter (cliente, restaurante, repartidor)
- [ ] **PASO 8:** Verificar que los datos se guardan correctamente en las tablas

---

## 🆘 TROUBLESHOOTING

### **❌ Error: "function does not exist"**
**Solución:** Asegúrate de ejecutar primero el script `NUEVO_08_create_register_rpcs_v2_CORREGIDO.sql`

### **❌ Error: "policy already exists"**
**Solución:** Ejecuta primero `09_cleanup_all_policies.sql` para limpiar todas las políticas

### **❌ Error: "relation does not exist"**
**Solución:** Verifica que tu `DATABASE_SCHEMA.sql` coincida con las tablas usadas en los scripts

### **❌ Error: "permission denied"**
**Solución:** Verifica que RLS esté habilitado y las políticas creadas correctamente

### **❌ Error: "Not authenticated"**
**Solución:** Asegúrate de llamar primero a `supabase.auth.signUp()` antes de llamar a las funciones RPC

---

## 🎉 RESULTADO FINAL ESPERADO

Al completar todos los pasos tendrás:

1. ✅ **3 funciones RPC profesionales** para registro atómico
2. ✅ **Políticas RLS consistentes** para seguridad
3. ✅ **Índices optimizados** para mejor performance
4. ✅ **Sistema de notificaciones** para admins
5. ✅ **Cuentas financieras automáticas** para restaurantes/repartidores
6. ✅ **Sincronización perfecta** entre `auth.users` ↔ `public.users` ↔ perfiles

---

## 📞 SOPORTE

Si encuentras algún problema:
1. Verifica el console log completo del error
2. Identifica en qué script ocurrió
3. Revisa la sección de Troubleshooting
4. Si persiste, reporta con contexto completo

---

**Creado:** 2025
**Última actualización:** Basado en `DATABASE_SCHEMA.sql` actual
**Versión:** v3 (CORREGIDA)
