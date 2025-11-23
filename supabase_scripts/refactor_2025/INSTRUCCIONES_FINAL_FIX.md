# ✅ SOLUCIÓN DEFINITIVA: Error 500 en Registro

## 🔍 PROBLEMA IDENTIFICADO

**Error:**
```
POST /auth/v1/signup 500 (Internal Server Error)
{"code":"unexpected_failure","message":"Database error saving new user"}
```

**Causa raíz:**
La función `ensure_client_profile_and_account()` en el archivo `2025-11-client-address-rpcs.sql` (líneas 21-23) **NO incluye el campo `status`** en el INSERT:

```sql
-- ❌ CÓDIGO PROBLEMÁTICO ACTUAL:
INSERT INTO public.client_profiles AS cp (user_id, updated_at)
VALUES (p_user_id, now())
```

**Pero tu tabla `client_profiles` SÍ tiene:**
- ✅ Columna `status` con `NOT NULL DEFAULT 'active'` (agregada en script 12)
- ✅ Constraint CHECK para validar valores: 'active', 'inactive', 'suspended'

El problema es que la función usa una **versión vieja** que no incluye `status`.

---

## ✅ SOLUCIÓN

He creado el archivo:

```
supabase_scripts/refactor_2025/FINAL_FIX_ensure_client_profile_and_account.sql
```

Este script:

1. ✅ **Elimina la función vieja** `ensure_client_profile_and_account()`
2. ✅ **Recrea la función con el campo `status`** incluido:
   ```sql
   INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
   VALUES (p_user_id, 'active', now(), now())
   ```
3. ✅ **Agrega logging detallado** en caso de error con RAISE WARNING
4. ✅ **Mantiene compatibilidad** con trigger `handle_new_user()`

---

## 📋 INSTRUCCIONES DE USO

### **PASO 1: Ejecutar el script de corrección**

1. Abre **Supabase SQL Editor**: https://app.supabase.com/project/[TU_PROJECT_ID]/sql/new
2. Copia y pega TODO el contenido de: 
   ```
   supabase_scripts/refactor_2025/FINAL_FIX_ensure_client_profile_and_account.sql
   ```
3. Haz clic en **"Run"** (▶️)
4. Deberías ver: ✅ Éxito sin errores

---

### **PASO 2: Verificar que se aplicó correctamente**

Ejecuta esto en el SQL Editor de Supabase para ver la definición actualizada:

```sql
SELECT pg_get_functiondef('public.ensure_client_profile_and_account(uuid)'::regprocedure);
```

**Debes ver** en la salida:
```sql
INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
VALUES (p_user_id, 'active'::text, now(), now())
```

✅ Si ves esa línea = **función actualizada correctamente**

---

### **PASO 3: Probar el registro de nuevo usuario**

1. Abre tu app en el navegador
2. Intenta registrar un usuario nuevo:
   - Email: `walfre.am@gmail.com` (o cualquier otro)
   - Contraseña: `Test123!`
   - Nombre: `Usuario Test`
   - Teléfono: `+52 1234567890`

3. **Debería funcionar correctamente** ✅

---

## ❌ SI SIGUE FALLANDO

Si después de ejecutar el script **todavía** obtienes error 500, ejecuta esto para debug:

```sql
-- 1. Ver la definición actual de la función
SELECT pg_get_functiondef('public.ensure_client_profile_and_account(uuid)'::regprocedure);

-- 2. Ver el trigger actual
SELECT pg_get_triggerdef(oid) 
FROM pg_trigger 
WHERE tgname = 'trg_handle_new_user_on_auth_users';

-- 3. Verificar columnas de client_profiles
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name = 'client_profiles'
ORDER BY ordinal_position;
```

Y compárteme los 3 resultados 👍

---

## 📊 VERIFICAR QUE EL USUARIO SE CREÓ CORRECTAMENTE

Después de registrar un usuario exitosamente, verifica que se creó en todas las tablas:

```sql
-- Reemplaza 'walfre.am@gmail.com' con el email que usaste
WITH user_info AS (
  SELECT id FROM auth.users WHERE email = 'walfre.am@gmail.com'
)
SELECT 
  'auth.users' as tabla,
  (SELECT COUNT(*) FROM auth.users WHERE id = (SELECT id FROM user_info)) as registros
UNION ALL
SELECT 
  'public.users',
  (SELECT COUNT(*) FROM public.users WHERE id = (SELECT id FROM user_info))
UNION ALL
SELECT 
  'client_profiles',
  (SELECT COUNT(*) FROM public.client_profiles WHERE user_id = (SELECT id FROM user_info))
UNION ALL
SELECT 
  'accounts',
  (SELECT COUNT(*) FROM public.accounts WHERE user_id = (SELECT id FROM user_info));
```

**Resultado esperado:**
```
tabla            | registros
-----------------+----------
auth.users       |     1
public.users     |     1
client_profiles  |     1
accounts         |     1
```

✅ Si ves **1** en todas las tablas = **registro exitoso completo**

---

## 🎯 RESUMEN EJECUTIVO

| Paso | Acción | Archivo |
|------|--------|---------|
| 1️⃣ | Ejecutar script de corrección | `FINAL_FIX_ensure_client_profile_and_account.sql` |
| 2️⃣ | Verificar función actualizada | Query SQL en PASO 2 |
| 3️⃣ | Probar registro | Desde tu app |
| 4️⃣ | Verificar usuario creado | Query SQL arriba ⬆️ |

---

## 💡 ¿POR QUÉ FALLABA?

**Antes:**
```sql
-- Función vieja en 2025-11-client-address-rpcs.sql
INSERT INTO client_profiles (user_id, updated_at)  -- ❌ Falta 'status'
VALUES (p_user_id, now())
```

**Tabla actual:**
```sql
CREATE TABLE client_profiles (
  user_id uuid,
  status text NOT NULL DEFAULT 'active',  -- ✅ Campo obligatorio
  ...
)
```

**Ahora (CORREGIDO):**
```sql
INSERT INTO client_profiles (user_id, status, created_at, updated_at)  -- ✅ Incluye 'status'
VALUES (p_user_id, 'active', now(), now())
```

---

## 🚀 SIGUIENTE PASO

Si el registro funciona correctamente después de este fix, los siguientes usuarios podrán:
- ✅ Registrarse sin errores
- ✅ Tener perfil de cliente con `status = 'active'`
- ✅ Tener cuenta financiera de tipo `client`
- ✅ Poder ser dados de baja cambiando `status` a `'inactive'` o `'suspended'`
