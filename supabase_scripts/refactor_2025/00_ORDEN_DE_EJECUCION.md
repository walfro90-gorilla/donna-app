# 📋 ORDEN DE EJECUCIÓN - REFACTORIZACIÓN SUPABASE

## 🎯 OBJETIVO
Refactorizar la base de datos para tener 3 procesos de registro estables y profesionales para:
- ✅ Clientes (`register_client`)
- ✅ Restaurantes (`register_restaurant`)
- ✅ Repartidores (`register_delivery_agent`)

---

## ✅ SCRIPTS YA EJECUTADOS (No ejecutar de nuevo)

| # | Script | Estado | Descripción |
|---|--------|--------|-------------|
| 01 | `01_backup_current_state.sql` | ✅ | Backup del estado actual |
| 02 | `02_cleanup_obsolete_functions.sql` | ✅ | Limpieza de funciones obsoletas |
| 03 | `03_cleanup_triggers.sql` | ✅ | Limpieza de triggers obsoletos |
| 04 | `04_migrate_data.sql` | ✅ | Migración de datos |
| 05 | `05_alter_tables.sql` | ✅ | Alteración de tablas |
| 06 | `06_create_register_client.sql` | ✅ | Creación de register_client |
| 07 | `07_create_register_restaurant.sql` | ✅ | Creación de register_restaurant |

---

## 🔧 SCRIPTS FALTANTES - EJECUTAR EN ESTE ORDEN

### **📂 Ubicación de scripts:**
```
supabase_scripts/refactor_2025/
```

---

### **✅ PASO 1: Limpiar políticas RLS**
```bash
Script: 09_cleanup_all_policies.sql
```
**Descripción:** Elimina todas las políticas RLS existentes para evitar conflictos de "policy already exists".

**Console output esperado:**
```
NOTICE:  Eliminada política: users_select_own de users
NOTICE:  Eliminada política: users_update_own de users
...
NOTICE:  ✅ Todas las políticas RLS han sido eliminadas exitosamente
```

---

### **✅ PASO 2: Crear funciones de registro (VERSIÓN CORREGIDA)**
```bash
Script: NUEVO_08_create_register_rpcs_v2_CORREGIDO.sql
```
**Descripción:** 
- Crea las 3 funciones de registro basadas en el esquema real de DATABASE_SCHEMA.sql
- Usa tablas correctas: `client_profiles`, `delivery_agent_profiles`, `restaurants`
- Roles correctos: `'cliente'`, `'restaurante'`, `'repartidor'`
- Crea automáticamente: `user_preferences`, `accounts`, `admin_notifications`

**Funciones creadas:**
1. ✅ `register_client(email, password, name, phone, address, lat, lon, address_structured)`
2. ✅ `register_restaurant(email, password, restaurant_name, contact_name, phone, address, lat, lon, address_structured)`
3. ✅ `register_delivery_agent(email, password, name, phone, vehicle_type)`

**Console output esperado:**
```
NOTICE:  Eliminada: public.register_client(...)
NOTICE:  Eliminada: public.register_restaurant(...)
NOTICE:  Eliminada: public.register_delivery_agent(...)
...
✅ FUNCIONES CREADAS EXITOSAMENTE | total_funciones: 3
```

---

### **✅ PASO 3: Crear políticas RLS actualizadas**
```bash
Script: NUEVO_09_update_rls_policies_v3_CORREGIDO.sql
```
**Descripción:** 
- Crea políticas RLS para: `users`, `client_profiles`, `restaurants`, `delivery_agent_profiles`, `user_preferences`, `accounts`
- Usuarios pueden ver/editar solo su propio contenido
- Admins pueden ver/editar todo
- Restaurantes aprobados son visibles públicamente

**Console output esperado:**
```
✅ POLÍTICAS RLS CREADAS EXITOSAMENTE | total_policies: 28
```

---

### **✅ PASO 4: Crear índices optimizados**
```bash
Script: NUEVO_11_create_indexes_OPTIMIZADO.sql
```
**Descripción:** 
- Crea índices para optimizar queries comunes
- Incluye índices compuestos para dashboards de restaurante/repartidor
- Índices para búsquedas por ubicación, status, fechas

**Console output esperado:**
```
✅ ÍNDICES CREADOS EXITOSAMENTE | total_indices: 45+
```

---

### **⚠️  PASO 5: (OPCIONAL) Crear trigger de auto-registro**
```bash
Script: NUEVO_12_create_auto_registration_trigger.sql
```
**Descripción:** 
- Sincroniza automáticamente `auth.users` → `public.users`
- Solo usar si quieres registro automático simple
- **NO RECOMENDADO** si necesitas capturar datos específicos por rol

**❌ NO ejecutar si:**
- Quieres control total del flujo de registro
- Necesitas capturar datos durante el registro (dirección, teléfono, etc.)

---

## 🔍 VERIFICACIÓN

### **Script de verificación:**
```bash
Script: NUEVO_10_test_registrations_CORREGIDO.sql
```
**Descripción:** 
- ✅ Verifica que las funciones existen y tienen firmas correctas
- ✅ Verifica que las tablas tienen las columnas correctas
- ✅ Verifica Foreign Keys
- 📋 Muestra instrucciones de cómo probar desde Flutter

**NOTA:** Este script NO ejecuta las funciones (requieren `auth.uid()`). Solo verifica que todo esté configurado correctamente.

---

## 🔍 DIAGNÓSTICO (Si algo falla)

Si algún script falla, ejecuta primero estos scripts de diagnóstico:

```bash
1. supabase_scripts/fixes/verify_functions_signatures.sql
2. supabase_scripts/fixes/01_verify_tables_exist.sql
```

---

## 🚀 FLUJO DE REGISTRO DESDE FLUTTER

### **1️⃣ Registro de Cliente**
```dart
// Paso 1: SignUp en auth
final authResponse = await supabase.auth.signUp(
  email: 'cliente@example.com',
  password: 'password123',
);

if (authResponse.user != null) {
  // Paso 2: Completar perfil
  final result = await supabase.rpc('register_client', params: {
    'p_email': 'cliente@example.com',
    'p_password': 'password123',
    'p_name': 'Juan Pérez',
    'p_phone': '+52 55 1234 5678',
    'p_address': 'Calle Principal 123',
    'p_lat': 19.4326,
    'p_lon': -99.1332,
    'p_address_structured': {
      'street': 'Calle Principal',
      'number': '123',
      'city': 'CDMX',
      'state': 'Ciudad de México',
      'country': 'México',
      'postal_code': '01000'
    }
  });
  print('Cliente registrado: $result');
}
```

### **2️⃣ Registro de Restaurante**
```dart
// Paso 1: SignUp en auth
final authResponse = await supabase.auth.signUp(
  email: 'restaurante@example.com',
  password: 'password123',
);

if (authResponse.user != null) {
  // Paso 2: Completar perfil
  final result = await supabase.rpc('register_restaurant', params: {
    'p_email': 'restaurante@example.com',
    'p_password': 'password123',
    'p_restaurant_name': 'Tacos El Güero',
    'p_contact_name': 'María González',
    'p_phone': '+52 55 9876 5432',
    'p_address': 'Avenida Reforma 456',
    'p_location_lat': 19.4330,
    'p_location_lon': -99.1350,
    'p_address_structured': {
      'street': 'Avenida Reforma',
      'number': '456',
      'city': 'CDMX',
      'state': 'Ciudad de México',
      'country': 'México',
      'postal_code': '06600'
    }
  });
  print('Restaurante registrado: $result');
}
```

### **3️⃣ Registro de Repartidor**
```dart
// Paso 1: SignUp en auth
final authResponse = await supabase.auth.signUp(
  email: 'repartidor@example.com',
  password: 'password123',
);

if (authResponse.user != null) {
  // Paso 2: Completar perfil
  final result = await supabase.rpc('register_delivery_agent', params: {
    'p_email': 'repartidor@example.com',
    'p_password': 'password123',
    'p_name': 'Carlos Ramírez',
    'p_phone': '+52 55 5555 5555',
    'p_vehicle_type': 'motocicleta'
  });
  print('Repartidor registrado: $result');
}
```

---

## ⚠️ NOTAS IMPORTANTES

### **Diferencias con scripts anteriores:**
1. ✅ **Tablas correctas**: Ahora usa `client_profiles` y `delivery_agent_profiles` (no `clients` ni `delivery_agents`)
2. ✅ **Roles correctos**: Usa `'cliente'`, `'restaurante'`, `'repartidor'` (según DATABASE_SCHEMA.sql)
3. ✅ **Campos correctos**: Todos los campos coinciden con el esquema real
4. ✅ **Foreign keys correctas**: `restaurants.user_id` tiene FK a `users.id`, no constraint `(user_id)` único

### **Qué se eliminó de scripts anteriores:**
- ❌ Referencias a tablas `clients` y `delivery_agents` (no existen)
- ❌ Roles incorrectos como `'client'` o `'delivery_agent'`
- ❌ Columnas que no existen en el esquema real

### **Qué se agregó:**
- ✅ Creación de notificaciones para admins
- ✅ Creación de cuentas financieras (`accounts`)
- ✅ Creación de preferencias de usuario (`user_preferences`)
- ✅ Validación de `auth.uid()` en todas las funciones

---

## 📊 VERIFICAR EJECUCIÓN EXITOSA

Después de ejecutar todos los scripts, verifica con estas queries:

```sql
-- 1. Ver funciones creadas
SELECT proname, prosrc 
FROM pg_proc 
WHERE proname IN ('register_client', 'register_restaurant', 'register_delivery_agent');

-- 2. Ver políticas RLS
SELECT tablename, policyname, cmd 
FROM pg_policies 
WHERE schemaname = 'public'
ORDER BY tablename;

-- 3. Ver índices creados
SELECT indexname, tablename 
FROM pg_indexes 
WHERE schemaname = 'public' AND indexname LIKE 'idx_%';
```

---

## 🆘 SOPORTE

Si encuentras errores durante la ejecución:
1. Copia el console log completo del error
2. Identifica en qué script falló
3. Ejecuta el script de diagnóstico correspondiente
4. Reporta el error con contexto

---

## ✅ CHECKLIST DE EJECUCIÓN

- [ ] 09_cleanup_all_policies.sql
- [ ] NUEVO_08_create_register_rpcs_v2_CORREGIDO.sql
- [ ] 09_update_rls_policies_v2.sql
- [ ] NUEVO_11_create_indexes_OPTIMIZADO.sql
- [ ] (OPCIONAL) NUEVO_12_create_auto_registration_trigger.sql
- [ ] NUEVO_10_test_registrations_CORREGIDO.sql (verificación)

---

## 🎉 RESULTADO ESPERADO

Al finalizar, tendrás:
1. ✅ 3 funciones RPC profesionales y estables para registro
2. ✅ Políticas RLS consistentes y seguras
3. ✅ Índices optimizados para mejorar performance
4. ✅ Sistema de notificaciones para admins
5. ✅ Cuentas financieras automáticas para restaurantes y repartidores
6. ✅ Sincronización perfecta entre `auth.users` y `public.users`
