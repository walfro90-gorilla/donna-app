# 🔧 INSTRUCCIONES CORREGIDAS - Solución de permisos

---

## ⚠️ PROBLEMA IDENTIFICADO

```
Error: Failed to run sql query: ERROR: 42501: must be owner of relation users
```

**Causa:** El script intentó modificar el trigger en `auth.users` pero tu usuario de Supabase no tiene permisos de `OWNER` sobre esa tabla.

---

## ✅ SOLUCIÓN

He creado scripts corregidos que **NO requieren** permisos de OWNER para funcionar.

---

## 📄 ARCHIVOS ACTUALIZADOS

### **1. Script de migración de tabla (sin cambios)**
```
supabase_scripts/refactor_2025/12_add_status_to_client_profiles.sql
```
✅ Este script funciona correctamente

---

### **2. Script de RPCs CORREGIDO (sin modificar trigger)**
```
supabase_scripts/refactor_2025/13_update_client_registration_rpc_FIXED.sql
```
✅ **NUEVO** - Solo actualiza funciones, NO toca el trigger

**Cambios:**
- ✅ Actualiza `ensure_client_profile_and_account()` para usar `status='active'`
- ✅ Actualiza `handle_new_user()` sin recrear el trigger
- ✅ Verifica que el trigger existente esté correcto
- ❌ NO intenta modificar `auth.users` (evita error de permisos)

---

### **3. Script para crear trigger (opcional)**
```
supabase_scripts/refactor_2025/14_create_trigger_manually.sql
```
⚠️ **SOLO SI** el trigger no existe (probablemente ya existe)

---

## 🚀 INSTRUCCIONES DE EJECUCIÓN CORREGIDAS

### **PASO 1: Agregar campo `status` (si no lo hiciste ya)**

Si **YA ejecutaste** el script `12_add_status_to_client_profiles.sql` correctamente, **SALTA este paso**.

Si no lo ejecutaste:
1. Abrir: **Supabase Dashboard > SQL Editor**
2. Copiar y pegar: `12_add_status_to_client_profiles.sql`
3. Ejecutar (Run)
4. ✅ Verificar mensaje: `[OK] Columna status existe`

---

### **PASO 2: Actualizar RPCs (VERSION CORREGIDA)**

1. Abrir: **Supabase Dashboard > SQL Editor**
2. Copiar y pegar: **`13_update_client_registration_rpc_FIXED.sql`** (el nuevo archivo)
3. Ejecutar (Run)
4. ✅ Verificar mensajes:
   ```
   [OK] Trigger existente encontrado: on_auth_user_created
   [INFO] El trigger YA LLAMA a ensure_client_profile_and_account()
   [OK] Funcion ensure_client_profile_and_account existe
   [OK] Funcion handle_new_user existe
   [OK] Columna status existe en client_profiles
   [SUCCESS] Sistema de registro de cliente actualizado correctamente
   ```

---

### **PASO 3: Verificar si necesitas crear el trigger**

**Opción A: El trigger YA EXISTE** (caso más común)

Si en el **PASO 2** viste el mensaje:
```
[OK] Trigger existente encontrado: on_auth_user_created
```

✅ **¡No necesitas hacer nada más!** El sistema ya está listo.

**Salta al PASO 4 directamente.**

---

**Opción B: El trigger NO EXISTE** (raro)

Si en el **PASO 2** viste el mensaje:
```
[WARNING] No se encontro trigger en auth.users
```

Entonces necesitas crear el trigger manualmente:

1. Abrir: **Supabase Dashboard > SQL Editor**
2. Copiar y pegar: `14_create_trigger_manually.sql`
3. Ejecutar (Run)
4. ✅ Verificar mensaje: `[SUCCESS] Trigger activo y funcionando`

**Nota:** Si este script también falla con error de permisos, contacta a Supabase Support.

---

### **PASO 4: Probar registro de usuario**

1. Abrir tu **app Flutter**
2. Ir a pantalla de **registro**
3. Crear nuevo usuario con email/password
4. ✅ **Resultado esperado:** Registro exitoso **SIN error 500**

---

## 🔍 VERIFICACIÓN RÁPIDA

### **1. Verificar columna `status`**

```sql
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'client_profiles' 
AND column_name = 'status';

-- ✅ DEBE RETORNAR:
-- status | text | 'active'::text
```

---

### **2. Verificar función actualizada**

```sql
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'ensure_client_profile_and_account';

-- ✅ DEBE CONTENER:
-- INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
-- VALUES (p_user_id, 'active', v_now, v_now)
```

---

### **3. Verificar trigger**

```sql
SELECT 
  t.tgname AS trigger_name,
  p.proname AS function_name,
  CASE t.tgenabled
    WHEN 'O' THEN 'enabled'
    WHEN 'D' THEN 'disabled'
  END AS status
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE n.nspname = 'auth' 
AND c.relname = 'users'
AND t.tgname IN ('on_auth_user_created', 'handle_new_user');

-- ✅ DEBE RETORNAR:
-- trigger_name: on_auth_user_created
-- function_name: handle_new_user
-- status: enabled
```

---

## 📊 ¿QUÉ CAMBIÓ EN LA SOLUCIÓN?

### **Script anterior (FALLÓ):**
```sql
-- ❌ Intentaba recrear el trigger (requiere permisos OWNER):
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users CASCADE;
CREATE TRIGGER on_auth_user_created ...
```

### **Script nuevo (FUNCIONA):**
```sql
-- ✅ Solo actualiza las funciones (no requiere permisos especiales):
CREATE OR REPLACE FUNCTION public.ensure_client_profile_and_account(...)
CREATE OR REPLACE FUNCTION public.handle_new_user(...)
-- No toca el trigger existente
```

---

## 🎯 FLUJO DE REGISTRO ACTUALIZADO

```
1. Usuario se registra con email/password
   ↓
2. Supabase Auth crea registro en auth.users
   ↓
3. Trigger on_auth_user_created se ejecuta (YA EXISTE)
   ↓
4. Función handle_new_user() (ACTUALIZADA) ejecuta:
   a. Crea registro en public.users (role='client')
   b. Llama a ensure_client_profile_and_account() (ACTUALIZADA)
      - Crea client_profiles con status='active'  ✅ NUEVO
      - Crea accounts con account_type='client'
   ↓
5. ✅ Usuario listo con perfil activo
```

---

## ✅ CHECKLIST FINAL

- [ ] **PASO 1:** Ejecutar `12_add_status_to_client_profiles.sql` (si no lo hiciste)
- [ ] **PASO 2:** Ejecutar `13_update_client_registration_rpc_FIXED.sql` (el corregido)
- [ ] **PASO 3:** Verificar si el trigger existe
  - [ ] Si existe: ✅ Listo, salta al PASO 4
  - [ ] Si no existe: Ejecutar `14_create_trigger_manually.sql`
- [ ] **PASO 4:** Probar registro de usuario en Flutter
  - [ ] Usuario se crea sin error 500
  - [ ] Verificar en Supabase que `status='active'`

---

## 🚨 SI TODAVÍA FALLA

### **Error: "must be owner of relation users"**

**Solución temporal (mientras contactas a Supabase):**

Puedes registrar usuarios usando el RPC directamente en lugar del trigger:

1. **En Flutter, después del signup exitoso:**

```dart
// Después de que Supabase Auth cree el usuario
final response = await supabase.rpc(
  'ensure_client_profile_and_account',
  params: {'p_user_id': user.id}
);
```

2. **Esto creará el profile y account manualmente**

---

### **Contactar a Supabase Support**

Si el trigger no existe y no puedes crearlo:

1. Ir a: **Supabase Dashboard > Support**
2. Explicar: "Need OWNER permissions on auth.users to create trigger"
3. Ellos pueden ejecutar el script por ti o darte permisos temporales

---

## 📌 RESUMEN

### **Lo que necesitas ejecutar:**

1. ✅ `12_add_status_to_client_profiles.sql` (agrega columna)
2. ✅ `13_update_client_registration_rpc_FIXED.sql` (actualiza funciones)
3. ⚠️ `14_create_trigger_manually.sql` (solo si el trigger no existe)

### **Resultado esperado:**

✅ Registro de usuarios funciona sin error 500
✅ `client_profiles` se crea con `status='active'`
✅ Sin problemas de permisos

---

**¡Ejecuta el script corregido y prueba de nuevo!** 🚀
