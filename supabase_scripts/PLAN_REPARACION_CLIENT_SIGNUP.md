# 🔧 PLAN DE REPARACIÓN QUIRÚRGICA - CLIENT SIGNUP

**Fecha:** 2025-01-XX  
**Problema:** Registros de clientes se crean vacíos (sin name, phone, lat, lon, address)

---

## 🔍 DIAGNÓSTICO FINAL

### ❌ CAUSA RAÍZ IDENTIFICADA:

**El trigger `on_auth_user_created` NO EXISTE en la tabla `auth.users`**

Por lo tanto:
1. ✅ Usuario se crea en `auth.users` (Supabase Auth funciona)
2. ❌ **NUNCA** se llama a `handle_new_user_signup_v2()` (no hay trigger)
3. ❌ No se copian los datos de `raw_user_meta_data` a `public.users`
4. ❌ No se crea `client_profiles` con ubicación
5. ❌ No se crea `user_preferences`

### 📊 EVIDENCIA:

**PARTE 4 de la auditoría:**
```
-- 4.3 Listar triggers en la tabla auth.users:
[NO RESULTS]  ← ⚠️ AQUÍ ESTÁ EL PROBLEMA
```

**PARTE 5 de la auditoría:**
```
-- 5.1 Ver últimos logs de debug_user_signup_log:
[Último log es de restaurante el 2025-11-10]
[NO HAY LOGS del cliente registrado el 2025-11-12]
```

---

## ✅ SOLUCIÓN QUIRÚRGICA

### 🎯 OBJETIVO:
**Crear el trigger faltante** que conecta `auth.users` con `handle_new_user_signup_v2()`

### 📋 PASOS:

#### **1. ELIMINAR FUNCIONES DUPLICADAS** ⚠️
Hay **3 versiones** de `ensure_user_profile_public()` con firmas diferentes:
- `ensure_user_profile_public(p_user_id, p_email, p_role, p_name, p_phone)`
- `ensure_user_profile_public(p_user_id, p_email, p_name, p_role, ...p_lat, p_lon, p_address_structured)`
- `ensure_user_profile_public(p_user_id, p_email, p_role, ...)`

**Problema:** Múltiples versiones causan confusión y pueden interferir con triggers.

**Acción:** Eliminar todas las versiones EXCEPTO la que usa `handle_new_user_signup_v2()`.

---

#### **2. CREAR TRIGGER FALTANTE** 🔥

**Trigger:** `on_auth_user_created`  
**Tabla:** `auth.users`  
**Evento:** `AFTER INSERT`  
**Función:** `handle_new_user_signup_v2()`

Este trigger:
- ✅ Se ejecuta automáticamente cuando Supabase Auth crea un usuario
- ✅ Lee `raw_user_meta_data` (name, phone, lat, lon, address_structured)
- ✅ Crea registro en `public.users` con todos los datos
- ✅ Crea `client_profiles` con ubicación
- ✅ Crea `user_preferences`
- ✅ Crea `accounts`
- ✅ Registra todo en `debug_user_signup_log`

---

#### **3. VERIFICAR Y OPTIMIZAR `handle_new_user_signup_v2()`** 🔧

**Verificar:**
- ✅ Extrae correctamente `lat`, `lon`, `address_structured` de metadata
- ✅ Inserta en `client_profiles` con ubicación
- ✅ Maneja conversión de tipos (text → double precision)
- ✅ Logs detallados para debugging

**Ya está correcta** según auditoría (líneas 386-388 de AUDITORIA_CLIENT_SIGNUP_REAL.md).

---

## 🚀 ARCHIVOS SQL A EJECUTAR

### **ARCHIVO 1: `FIX_CLIENT_SIGNUP_TRIGGER.sql`** ⚡ **← EJECUTAR ESTE**

**Qué hace:**
1. **Elimina funciones duplicadas** de `ensure_user_profile_public()`
2. **Crea el trigger faltante** `on_auth_user_created` en `auth.users`
3. **Verifica** que `handle_new_user_signup_v2()` existe

**Seguridad:**
- ✅ NO toca funciones de restaurant
- ✅ NO toca funciones de delivery_agent
- ✅ NO modifica tablas
- ✅ Solo crea el trigger faltante

---

## 🧪 PLAN DE PRUEBAS

### **DESPUÉS DE EJECUTAR EL SQL:**

1. **Crear un nuevo cliente de prueba:**
   ```
   - Nombre: "Test Cliente Fix"
   - Email: "test_fix_trigger@test.com"
   - Teléfono: "+50912345678"
   - Ubicación: lat=14.1234, lon=-90.5678
   ```

2. **Verificar en Supabase:**
   ```sql
   -- Ver usuario creado
   SELECT id, email, name, phone, role 
   FROM public.users 
   WHERE email = 'test_fix_trigger@test.com';
   
   -- Ver perfil con ubicación
   SELECT user_id, lat, lon, address, address_structured
   FROM public.client_profiles 
   WHERE user_id = (SELECT id FROM public.users WHERE email = 'test_fix_trigger@test.com');
   
   -- Ver logs de debug
   SELECT * FROM public.debug_user_signup_log 
   WHERE email = 'test_fix_trigger@test.com'
   ORDER BY created_at DESC;
   ```

3. **Resultado esperado:**
   - ✅ `users.name` = "Test Cliente Fix"
   - ✅ `users.phone` = "+50912345678"
   - ✅ `client_profiles.lat` = 14.1234
   - ✅ `client_profiles.lon` = -90.5678
   - ✅ Logs muestran todo el proceso

---

## ⚠️ NOTAS IMPORTANTES

### **POR QUÉ NO SE ROMPIÓ ANTES:**
- Restaurant y Delivery Agent usan **RPCs atómicas** que NO dependen de triggers:
  - `register_restaurant_atomic()`
  - `register_delivery_agent_atomic()`
- Cliente **SÍ depende** del trigger `on_auth_user_created` que estaba faltando

### **QUÉ NO SE TOCARÁ:**
- ✅ Funciones de restaurant (`register_restaurant_atomic`, etc.)
- ✅ Funciones de delivery_agent (`register_delivery_agent_atomic`, etc.)
- ✅ Funciones de admin
- ✅ Tablas existentes
- ✅ Datos existentes

### **SOLO SE AGREGA:**
- ✅ Trigger faltante en `auth.users`
- ✅ Limpieza de funciones duplicadas que causan confusión

---

## 📝 PRÓXIMOS PASOS

1. ✅ **EJECUTAR:** `FIX_CLIENT_SIGNUP_TRIGGER.sql`
2. ✅ **PROBAR:** Crear un nuevo cliente
3. ✅ **VERIFICAR:** Datos completos en `users` y `client_profiles`
4. ✅ **CONFIRMAR:** Logs en `debug_user_signup_log`

---

## 🎯 RESULTADO FINAL ESPERADO

**Cuando un cliente se registra desde Flutter:**

```dart
// Flutter envía:
await supabase.auth.signUp(
  email: 'cliente@test.com',
  password: 'password123',
  data: {
    'role': 'client',
    'name': 'Juan Pérez',
    'phone': '+50912345678',
    'lat': 14.1234,
    'lon': -90.5678,
    'address_structured': {...}
  }
);
```

**Supabase automáticamente:**
1. ✅ Crea usuario en `auth.users` (Supabase Auth)
2. ✅ **TRIGGER** ejecuta `handle_new_user_signup_v2()`
3. ✅ Crea registro completo en `public.users` (con name, phone)
4. ✅ Crea `client_profiles` (con lat, lon, address)
5. ✅ Crea `user_preferences`
6. ✅ Crea `accounts` (balance 0.0)
7. ✅ Registra todo en logs de debug

**Sin errores. Sin datos faltantes. Totalmente automático.** ✨

---

**END OF PLAN**
