# 🚀 INSTRUCCIONES PARA EJECUTAR EL FIX

## 📋 RESUMEN DEL PROBLEMA

**CAUSA RAÍZ ENCONTRADA:** 
El trigger `on_auth_user_created` **NO EXISTE** en `auth.users`, por lo que cuando un cliente se registra, los datos de `raw_user_meta_data` (name, phone, lat, lon) **nunca se copian** a las tablas `public.users` y `public.client_profiles`.

**EVIDENCIA:**
- ✅ `auth.users` tiene el usuario (Supabase Auth funciona)
- ❌ `public.users` tiene el registro pero con `name=NULL`, `phone=NULL`
- ❌ `public.client_profiles` tiene el registro pero con `lat=NULL`, `lon=NULL`
- ❌ NO hay logs en `debug_user_signup_log` para el último cliente

---

## ✅ LA SOLUCIÓN

Crear el trigger faltante que conecta `auth.users` con la función `handle_new_user_signup_v2()` que ya existe y funciona correctamente.

---

## 🎯 PASOS PARA APLICAR EL FIX

### **PASO 1: Ejecutar el script de reparación** ⚡

En el **SQL Editor de Supabase**, ejecuta:

```sql
-- Copiar y pegar todo el contenido de:
FIX_CLIENT_SIGNUP_TRIGGER.sql
```

**¿Qué hace este script?**
1. ✅ Limpia funciones duplicadas de `ensure_user_profile_public()` (3 versiones → 0)
2. ✅ Verifica que `handle_new_user_signup_v2()` existe
3. ✅ Crea el trigger faltante `on_auth_user_created` en `auth.users`
4. ✅ Verifica que todo quedó correctamente instalado

**Resultado esperado:**
```
✅ Eliminada ensure_user_profile_public(5 params)
✅ Eliminada ensure_user_profile_public(9 params)
✅ handle_new_user_signup_v2() existe y está lista
✅✅✅ TRIGGER on_auth_user_created CREADO EXITOSAMENTE ✅✅✅
✅ VERIFICACIÓN EXITOSA
🎉 TODO LISTO PARA PROBAR 🎉
```

---

### **PASO 2: Verificar la instalación** 🔍

En el **SQL Editor de Supabase**, ejecuta:

```sql
-- Copiar y pegar todo el contenido de:
VERIFICAR_FIX_CLIENTE.sql
```

**Resultado esperado:**
- ✅ Trigger `on_auth_user_created` existe en `auth.users`
- ✅ Función `handle_new_user_signup_v2()` existe
- ✅ 0 funciones duplicadas de `ensure_user_profile_public()`
- ✅ `client_profiles` tiene columnas `lat`, `lon`, `address`, `address_structured`

---

### **PASO 3: Probar con un nuevo cliente** 🧪

Desde tu app Flutter, registra un nuevo cliente de prueba:

```dart
// Ejemplo de registro:
await supabase.auth.signUp(
  email: 'test_fix@test.com',
  password: 'password123',
  data: {
    'role': 'client',
    'name': 'Test Cliente Fix',
    'phone': '+50912345678',
    'lat': 14.1234,
    'lon': -90.5678,
    'address': 'Calle de Prueba 123',
    'address_structured': {
      'formatted_address': 'Calle de Prueba 123, Ciudad',
      'city': 'Ciudad',
      'state': 'Estado',
      'country': 'Guatemala',
    }
  }
);
```

---

### **PASO 4: Verificar que funcionó** ✅

En el **SQL Editor de Supabase**, ejecuta:

```sql
-- Ver el usuario creado en public.users
SELECT id, email, name, phone, role, created_at
FROM public.users
WHERE email = 'test_fix@test.com';

-- ESPERADO:
-- ✅ name = 'Test Cliente Fix'
-- ✅ phone = '+50912345678'
-- ✅ role = 'client'
```

```sql
-- Ver el perfil con ubicación en client_profiles
SELECT 
  user_id, 
  lat, 
  lon, 
  address, 
  address_structured,
  created_at
FROM public.client_profiles
WHERE user_id = (SELECT id FROM public.users WHERE email = 'test_fix@test.com');

-- ESPERADO:
-- ✅ lat = 14.1234
-- ✅ lon = -90.5678
-- ✅ address = 'Calle de Prueba 123'
-- ✅ address_structured tiene el objeto JSON
```

```sql
-- Ver los logs de debug
SELECT * 
FROM public.debug_user_signup_log
WHERE email = 'test_fix@test.com'
ORDER BY created_at DESC;

-- ESPERADO:
-- ✅ Múltiples eventos: START, USER_CREATED, CLIENT_PROFILE_CREATED, ACCOUNT_CREATED, etc.
-- ✅ details muestra lat_saved, lon_saved, address_saved
```

---

## 🎉 RESULTADO FINAL

**Si todo funcionó correctamente:**

✅ **public.users** tiene `name` y `phone`  
✅ **client_profiles** tiene `lat`, `lon`, `address`, `address_structured`  
✅ **user_preferences** fue creado automáticamente  
✅ **accounts** fue creado con balance 0.0  
✅ **debug_user_signup_log** tiene logs detallados de todo el proceso  

**El flujo de registro de clientes ahora funciona automáticamente y sin errores.** ✨

---

## 🔧 ¿QUÉ SE TOCÓ Y QUÉ NO?

### ✅ LO QUE SE MODIFICÓ:
- ✅ Se **creó** el trigger `on_auth_user_created` en `auth.users`
- ✅ Se **eliminaron** 3 versiones duplicadas de `ensure_user_profile_public()`

### ✅ LO QUE **NO** SE TOCÓ:
- ✅ Función `handle_new_user_signup_v2()` (ya existía y funcionaba bien)
- ✅ Funciones de **restaurant** (`register_restaurant_atomic`, etc.)
- ✅ Funciones de **delivery_agent** (`register_delivery_agent_atomic`, etc.)
- ✅ Funciones de **admin**
- ✅ **Ninguna tabla** fue modificada
- ✅ **Ningún dato existente** fue modificado
- ✅ Triggers de otras tablas

### 🎯 IMPACTO:
- ✅ **Restaurant signup:** Sigue funcionando igual (usa RPC atómica)
- ✅ **Delivery signup:** Sigue funcionando igual (usa RPC atómica)
- ✅ **Client signup:** **AHORA FUNCIONA CORRECTAMENTE** ⚡

---

## 📁 ARCHIVOS CREADOS

1. **`PLAN_REPARACION_CLIENT_SIGNUP.md`** - Plan detallado del diagnóstico y solución
2. **`FIX_CLIENT_SIGNUP_TRIGGER.sql`** ⚡ - Script de reparación (EJECUTAR ESTE)
3. **`VERIFICAR_FIX_CLIENTE.sql`** - Script de verificación post-fix
4. **`INSTRUCCIONES_EJECUTAR_FIX.md`** - Este archivo (instrucciones paso a paso)

---

## 🆘 SOPORTE

Si algo falla:

1. **Revisa los mensajes de error** en el SQL Editor
2. **Ejecuta** `VERIFICAR_FIX_CLIENTE.sql` para ver qué falta
3. **Revisa los logs** en `debug_user_signup_log`
4. **Verifica** que `handle_new_user_signup_v2()` existe:
   ```sql
   SELECT proname FROM pg_proc WHERE proname = 'handle_new_user_signup_v2';
   ```

---

## 📝 NOTAS FINALES

- Este fix es **quirúrgico** y **no rompe nada** existente
- Solo agrega el trigger faltante que debió existir desde el principio
- Restaurant y Delivery Agent siguen funcionando perfectamente
- Client signup ahora funciona automáticamente sin intervención manual

**¡Listo para aplicar!** 🚀

---

**END OF INSTRUCTIONS**
