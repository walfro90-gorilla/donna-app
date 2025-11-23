# 🎯 RESUMEN EJECUTIVO: REFACTORIZACIÓN DE SIGNUP

## 📊 ESTADO ACTUAL

**Problema:** El signup devuelve error 500 porque la función `handle_new_user()` asume que todos los usuarios son clientes, ignorando roles de restaurante y repartidor.

**Causa raíz:**
- Función obsoleta que no maneja roles correctamente
- 13+ funciones RPC redundantes que intentan hacer signup manualmente
- Triggers conflictivos que bloquean inserciones
- Lógica fragmentada entre múltiples funciones

---

## ✅ SOLUCIÓN IMPLEMENTADA

### **Arquitectura nueva:**

```
Flutter: supabase.auth.signUp({email, password, data: {role, name}})
    ↓
Supabase Auth: Crea usuario en auth.users
    ↓
Trigger: on_auth_user_created (AFTER INSERT)
    ↓
Función maestra: master_handle_signup()
    ├─ Crea public.users (con rol correcto)
    ├─ CASE rol:
    │   ├─ cliente → client_profiles + account (client)
    │   ├─ restaurante → restaurants (status=pending, sin account)
    │   └─ repartidor → delivery_agent_profiles (account_state=pending, sin account)
    ├─ Crea user_preferences
    └─ Si falla → ROLLBACK completo
```

### **Características:**
- ✅ **Atómica:** Rollback completo si falla cualquier paso
- ✅ **Profesional:** Una sola función maestra (vs 13+ funciones obsoletas)
- ✅ **Extensible:** Fácil agregar nuevos roles
- ✅ **Debuggeable:** Logs exhaustivos en cada paso
- ✅ **Segura:** SECURITY DEFINER con search_path fijo

---

## 📁 SCRIPTS CREADOS

### **Carpeta:** `supabase_scripts/refactor_2025/SIGNUP_REFACTOR/`

```
SIGNUP_REFACTOR/
├── 00_README.md ................................. Instrucciones generales
│
├── FASE 1: LIMPIEZA (scripts 01-03)
│   ├── 01_cleanup_backup_obsolete.sql ........... Backup de funciones antiguas
│   ├── 02_cleanup_disable_triggers.sql .......... Desactivar triggers conflictivos
│   └── 03_cleanup_drop_rpcs.sql ................. Eliminar 13+ RPCs obsoletos
│
├── FASE 2: IMPLEMENTACIÓN (scripts 04-06)
│   ├── 04_implementation_master_function.sql .... Crear master_handle_signup()
│   ├── 05_implementation_replace_trigger.sql .... Reemplazar trigger en auth.users
│   └── 06_implementation_grant_permissions.sql .. Configurar permisos
│
├── FASE 3: VALIDACIÓN (scripts 07-08)
│   ├── 07_validation_test_signup.sql ............ Tests de signup (3 roles)
│   └── 08_validation_cleanup_tests.sql .......... Limpiar datos de prueba
│
├── MASTER_PLAN_SIGNUP_REFACTOR.md ............... Plan completo detallado
└── RESUMEN_EJECUTIVO.md (este archivo) .......... Resumen ejecutivo
```

---

## 🚀 ORDEN DE EJECUCIÓN

### **1. FASE 1: LIMPIEZA (10 min)**
```bash
# En Supabase SQL Editor, ejecutar en orden:
01_cleanup_backup_obsolete.sql      # Hace backup de funciones
02_cleanup_disable_triggers.sql     # Desactiva triggers problemáticos
03_cleanup_drop_rpcs.sql            # Elimina RPCs obsoletos
```

### **2. FASE 2: IMPLEMENTACIÓN (5 min)**
```bash
04_implementation_master_function.sql   # Crea función maestra
05_implementation_replace_trigger.sql   # Reemplaza trigger
06_implementation_grant_permissions.sql # Configura permisos
```

### **3. FASE 3: VALIDACIÓN (5 min)**
```bash
07_validation_test_signup.sql        # Ejecuta tests automáticos
08_validation_cleanup_tests.sql      # Limpia datos de prueba
```

**Tiempo total:** ~20 minutos

---

## 🎯 ROLES SOPORTADOS

### **1. CLIENTE (cliente)**
Signup crea automáticamente:
- ✅ `public.users` (role='cliente')
- ✅ `client_profiles` (status='active')
- ✅ `accounts` (account_type='client', balance=0)
- ✅ `user_preferences`

**Metadata requerida:**
```dart
await supabase.auth.signUp(
  email: 'cliente@example.com',
  password: 'password123',
  data: {
    'role': 'cliente',
    'name': 'Juan Pérez',
    'phone': '+1234567890' // opcional
  }
);
```

### **2. RESTAURANTE (restaurante)**
Signup crea automáticamente:
- ✅ `public.users` (role='restaurante')
- ✅ `restaurants` (status='pending', online=false)
- ✅ `user_preferences`
- ❌ `accounts` NO se crea (se crea cuando admin aprueba)

**Metadata requerida:**
```dart
await supabase.auth.signUp(
  email: 'restaurante@example.com',
  password: 'password123',
  data: {
    'role': 'restaurante',
    'name': 'Mi Restaurante',
    'phone': '+1234567890' // opcional
  }
);
```

### **3. REPARTIDOR (repartidor)**
Signup crea automáticamente:
- ✅ `public.users` (role='repartidor')
- ✅ `delivery_agent_profiles` (status='pending', account_state='pending')
- ✅ `user_preferences`
- ❌ `accounts` NO se crea (se crea cuando admin aprueba)

**Metadata requerida:**
```dart
await supabase.auth.signUp(
  email: 'repartidor@example.com',
  password: 'password123',
  data: {
    'role': 'repartidor',
    'name': 'Carlos Delivery',
    'phone': '+1234567890' // opcional
  }
);
```

### **4. ADMIN (admin)** *(edge case)*
Signup crea automáticamente:
- ✅ `public.users` (role='admin')
- ✅ `user_preferences`
- ❌ No se crean profiles adicionales

---

## 🔍 DEBUGGING

### **Ver logs de signup:**
```sql
SELECT 
  source, 
  event, 
  role, 
  email, 
  details, 
  created_at
FROM debug_user_signup_log
WHERE email = 'usuario@example.com'
ORDER BY created_at DESC;
```

### **Ver usuarios creados recientemente:**
```sql
SELECT 
  u.id, 
  u.email, 
  u.role, 
  u.name,
  CASE WHEN cp.user_id IS NOT NULL THEN '✅' ELSE '❌' END as has_client_profile,
  CASE WHEN r.user_id IS NOT NULL THEN '✅' ELSE '❌' END as has_restaurant,
  CASE WHEN dap.user_id IS NOT NULL THEN '✅' ELSE '❌' END as has_delivery_profile,
  CASE WHEN a.user_id IS NOT NULL THEN '✅' ELSE '❌' END as has_account
FROM users u
LEFT JOIN client_profiles cp ON cp.user_id = u.id
LEFT JOIN restaurants r ON r.user_id = u.id
LEFT JOIN delivery_agent_profiles dap ON dap.user_id = u.id
LEFT JOIN accounts a ON a.user_id = u.id
WHERE u.created_at > now() - interval '1 hour'
ORDER BY u.created_at DESC;
```

### **Ver funciones respaldadas:**
```sql
SELECT 
  function_name, 
  reason_obsolete, 
  backed_up_at
FROM _backup_obsolete_functions
ORDER BY backed_up_at DESC;
```

---

## 🚨 ROLLBACK (si algo sale mal)

Si necesitas revertir los cambios:

```sql
-- 1. Restaurar trigger anterior
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created 
  AFTER INSERT ON auth.users
  FOR EACH ROW 
  EXECUTE FUNCTION public.handle_new_user();

-- 2. Reactivar triggers antiguos (si es necesario)
ALTER TABLE public.delivery_agent_profiles ENABLE TRIGGER ALL;
ALTER TABLE public.users ENABLE TRIGGER ALL;

-- 3. Restaurar funciones desde backup (si es necesario)
-- Ver el código en _backup_obsolete_functions y ejecutarlo manualmente
```

---

## ✅ VERIFICACIÓN POST-IMPLEMENTACIÓN

### **1. Signup de cliente desde Flutter:**
```dart
final response = await supabase.auth.signUp(
  email: 'test_cliente@test.com',
  password: 'Test123!',
  data: {'role': 'cliente', 'name': 'Test Cliente'}
);
```

**Verificar en SQL:**
```sql
SELECT * FROM debug_user_signup_log WHERE email = 'test_cliente@test.com';
SELECT * FROM users WHERE email = 'test_cliente@test.com';
SELECT * FROM client_profiles WHERE user_id = (SELECT id FROM users WHERE email = 'test_cliente@test.com');
SELECT * FROM accounts WHERE user_id = (SELECT id FROM users WHERE email = 'test_cliente@test.com');
```

### **2. Signup de restaurante desde Flutter:**
```dart
final response = await supabase.auth.signUp(
  email: 'test_restaurant@test.com',
  password: 'Test123!',
  data: {'role': 'restaurante', 'name': 'Test Restaurant'}
);
```

**Verificar en SQL:**
```sql
SELECT * FROM restaurants WHERE user_id = (SELECT id FROM users WHERE email = 'test_restaurant@test.com');
-- Verificar que status='pending' y NO existe account aún
```

### **3. Signup de repartidor desde Flutter:**
```dart
final response = await supabase.auth.signUp(
  email: 'test_delivery@test.com',
  password: 'Test123!',
  data: {'role': 'repartidor', 'name': 'Test Delivery'}
);
```

**Verificar en SQL:**
```sql
SELECT * FROM delivery_agent_profiles WHERE user_id = (SELECT id FROM users WHERE email = 'test_delivery@test.com');
-- Verificar que account_state='pending' y NO existe account aún
```

---

## 📊 MÉTRICAS DE ÉXITO

### **Antes de la refactorización:**
- ❌ Error 500 en signup
- ❌ 13+ funciones redundantes
- ❌ Triggers conflictivos
- ❌ Lógica fragmentada
- ❌ Sin logs de debugging
- ❌ Sin rollback en errores

### **Después de la refactorización:**
- ✅ Signup funciona para los 3 roles
- ✅ Una sola función maestra
- ✅ Triggers desactivados/eliminados
- ✅ Lógica centralizada
- ✅ Logs exhaustivos en cada paso
- ✅ Rollback automático en errores

---

## 🎯 PRÓXIMOS PASOS

1. **Ejecutar los 8 scripts** en orden en el SQL Editor de Supabase
2. **Probar signup desde Flutter** con los 3 roles
3. **Verificar logs** en `debug_user_signup_log`
4. **Monitorear primeros signups en producción**
5. **Después de 1 semana sin problemas:** eliminar tabla `_backup_obsolete_functions`

---

## 💡 NOTAS IMPORTANTES

### **Permisos:**
- ✅ La función `master_handle_signup()` solo puede ser ejecutada por postgres (via trigger)
- ✅ Los usuarios NO pueden llamar RPCs de signup manualmente
- ✅ El signup solo funciona via `supabase.auth.signUp()`

### **RLS (Row Level Security):**
- ⚠️ Asegúrate de que las RLS policies estén activas en:
  - `public.users`
  - `public.client_profiles`
  - `public.delivery_agent_profiles`
  - `public.restaurants`
  - `public.accounts`

### **Aprobación de usuarios:**
- Los **restaurantes** y **repartidores** requieren aprobación del admin antes de poder operar
- El account se crea automáticamente cuando el admin aprueba (trigger `create_account_on_user_approval`)
- Los **clientes** NO requieren aprobación y pueden usar la app inmediatamente

---

## 📞 SOPORTE

Si encuentras algún problema:

1. **Revisa los logs:**
   ```sql
   SELECT * FROM debug_user_signup_log ORDER BY created_at DESC LIMIT 50;
   ```

2. **Verifica el trigger:**
   ```sql
   SELECT * FROM pg_trigger WHERE tgname = 'on_auth_user_created';
   ```

3. **Verifica la función:**
   ```sql
   SELECT pg_get_functiondef(oid) 
   FROM pg_proc 
   WHERE proname = 'master_handle_signup';
   ```

4. **Si es necesario, ejecuta ROLLBACK** (ver sección de Rollback arriba)

---

✅ **¡LISTO PARA IMPLEMENTACIÓN!**

Todos los scripts están creados y listos para ejecutar. Simplemente sigue el orden numérico (01 → 08) y verifica cada paso.
