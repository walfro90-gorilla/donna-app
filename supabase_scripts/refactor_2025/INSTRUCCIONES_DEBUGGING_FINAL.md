# 🔧 INSTRUCCIONES DE DEBUGGING - ERROR 500 EN REGISTRO

## 🎯 PROBLEMA

El registro de usuarios falla con:
```
POST /auth/v1/signup 500 (Internal Server Error)
{"code":"unexpected_failure","message":"Database error saving new user"}
```

## ✅ CAMPO `status` YA ESTÁ CREADO

Confirmamos que la columna `status` **SÍ existe** en `client_profiles` (ver screenshot).

## 🔍 DIAGNÓSTICO PROFUNDO

El problema puede ser:

1. **La función `ensure_client_profile_and_account()` en la base de datos NO está actualizada**
   - Es posible que esté usando una versión vieja sin el campo `status`
   
2. **El trigger `handle_new_user()` está fallando silenciosamente**
   - Supabase solo muestra "Database error saving new user" sin más detalles

3. **Otro error desconocido dentro del trigger**
   - Necesitamos logging para verlo

---

## 🛠️ SOLUCIÓN: EJECUTAR SCRIPTS EN ORDEN

### **📄 PASO 1: DIAGNÓSTICO**

Ejecuta este script para ver el estado actual:

```sql
-- Ubicación: supabase_scripts/refactor_2025/DIAGNOSTIC_check_current_trigger.sql
```

Este script te mostrará:
- ✅ La definición completa de `ensure_client_profile_and_account()`
- ✅ La definición completa de `handle_new_user()`
- ✅ El trigger activo en `auth.users`
- ✅ Las columnas actuales de `client_profiles`

**🎯 BUSCA EN LA SALIDA:**
- ¿La función `ensure_client_profile_and_account()` incluye `status`?
- ¿La función tiene `INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)`?

---

### **📄 PASO 2: APLICAR FIX CON LOGGING**

Si el diagnóstico muestra que la función NO incluye `status`, ejecuta:

```sql
-- Ubicación: supabase_scripts/refactor_2025/FIX_FINAL_with_deep_logging.sql
```

Este script:
1. ✅ Crea tabla `trigger_debug_log` para logging detallado
2. ✅ Actualiza `ensure_client_profile_and_account()` con:
   - Inserción correcta con campo `status='active'`
   - Logging en cada paso
   - Manejo robusto de errores
3. ✅ Actualiza `handle_new_user()` con:
   - Captura de excepciones
   - Logging detallado
4. ✅ Verifica que el trigger existe (sin intentar modificarlo)

---

### **📄 PASO 3: PROBAR REGISTRO**

1. **Intenta crear un usuario nuevo desde Flutter:**
   ```
   Email: test@example.com
   Password: Test123!
   ```

2. **Si falla, ejecuta este query para ver los logs:**
   ```sql
   SELECT 
     ts,
     function_name,
     event,
     details,
     error_message,
     stack_trace
   FROM public.trigger_debug_log 
   WHERE user_id IN (
     SELECT id FROM auth.users WHERE email = 'test@example.com'
   )
   ORDER BY ts DESC 
   LIMIT 20;
   ```

3. **Analiza los logs:**
   - Busca el evento `ERROR_EXCEPTION` o `PROFILE_CREATION_ERROR`
   - Revisa el campo `error_message` para ver el error exacto
   - El campo `details->step` te dirá en qué parte del código falló

---

## 🔍 POSIBLES ERRORES Y SOLUCIONES

### **Error: "column 'status' does not exist"**

**Causa:** La función no se actualizó correctamente.

**Solución:** Vuelve a ejecutar `FIX_FINAL_with_deep_logging.sql`

---

### **Error: "must be owner of relation users"**

**Causa:** Tu usuario no tiene permisos para modificar el trigger en `auth.users`.

**Solución temporal:** 
- La función `ensure_client_profile_and_account()` funciona sin necesidad de trigger
- Puedes llamarla manualmente después del registro en Flutter
- O contacta a Supabase para que te den permisos de OWNER

---

### **Error: "duplicate key value violates unique constraint"**

**Causa:** El usuario ya existe de un intento anterior fallido.

**Solución:** Elimina el usuario de `auth.users` antes de intentar de nuevo:
```sql
-- CUIDADO: Esto eliminará el usuario completamente
DELETE FROM auth.users WHERE email = 'test@example.com';
```

---

### **Error: "relation 'user_preferences' does not exist"**

**Causa:** La tabla `user_preferences` no existe.

**Solución:** Comenta esta sección en `FIX_FINAL_with_deep_logging.sql`:
```sql
-- Asegurar user_preferences
-- INSERT INTO public.user_preferences (user_id, created_at, updated_at)
-- VALUES (p_user_id, v_now, v_now)
-- ON CONFLICT (user_id) DO NOTHING;
```

---

## 📊 VERIFICACIÓN FINAL

Una vez que el registro funcione, verifica:

```sql
-- 1. Usuario en auth.users
SELECT id, email, created_at FROM auth.users WHERE email = 'test@example.com';

-- 2. Usuario en public.users
SELECT id, email, role FROM public.users WHERE email = 'test@example.com';

-- 3. Profile de cliente con status
SELECT user_id, status, created_at FROM public.client_profiles 
WHERE user_id IN (SELECT id FROM auth.users WHERE email = 'test@example.com');

-- 4. Cuenta financiera
SELECT id, user_id, account_type, balance FROM public.accounts 
WHERE user_id IN (SELECT id FROM auth.users WHERE email = 'test@example.com');
```

**✅ ESPERADO:**
- ✅ `auth.users`: 1 registro
- ✅ `public.users`: 1 registro con `role='client'`
- ✅ `client_profiles`: 1 registro con `status='active'`
- ✅ `accounts`: 1 registro con `account_type='client'` y `balance=0.00`

---

## 🎯 RESUMEN EJECUTIVO

| PASO | ACCIÓN | RESULTADO ESPERADO |
|------|--------|-------------------|
| 1️⃣ | Ejecutar `DIAGNOSTIC_check_current_trigger.sql` | Ver definición actual de funciones |
| 2️⃣ | Ejecutar `FIX_FINAL_with_deep_logging.sql` | Actualizar funciones con logging |
| 3️⃣ | Intentar registro desde Flutter | Capturar logs detallados |
| 4️⃣ | Revisar `trigger_debug_log` | Identificar paso exacto donde falla |
| 5️⃣ | Aplicar solución específica | Según error identificado |

---

## 🆘 SI TODAVÍA FALLA

Envíame:
1. **Resultado completo del PASO 1 (diagnóstico)**
2. **Resultado de la query de logs del PASO 3**
3. **Screenshot del error en Flutter**

Con esa información podré darte la solución quirúrgica exacta.

---

**¿Listo para empezar? 👉 Ejecuta `DIAGNOSTIC_check_current_trigger.sql` primero.**
