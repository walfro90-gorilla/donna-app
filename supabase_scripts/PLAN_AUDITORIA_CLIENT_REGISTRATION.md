# 🔍 PLAN DE AUDITORÍA Y REPARACIÓN - Registro de Cliente

## 📊 DIAGNÓSTICO ACTUAL

### ✅ **LO QUE FUNCIONA:**
1. ✅ Usuario se crea correctamente en `auth.users`
2. ✅ Registro se crea en `public.users` (pero con `name=NULL`, `phone=NULL`)
3. ✅ Registro se crea en `public.accounts` (account_type='client')
4. ✅ Registro se crea en `public.client_profiles` (pero SIN ubicación)

### ❌ **LO QUE FALTA:**
1. ❌ En `public.users`: `name` = NULL, `phone` = NULL
2. ❌ En `public.client_profiles`: `address` = NULL, `lat` = NULL, `lon` = NULL, `address_structured` = NULL

---

## 🔎 POSIBLES CAUSAS

### **Hipótesis 1: RPC `ensure_user_profile_public()` no recibe los datos**
- **Evidencia:** Flutter SÍ envía los datos (logs confirmados en líneas 194-224 de `register_screen.dart`)
- **Acción:** ✅ Verificar logs de Supabase para confirmar que el RPC recibe los parámetros

### **Hipótesis 2: TRIGGER `handle_new_user_signup_v2()` sobrescribe los datos**
- **Evidencia:** Existe un trigger que se dispara DESPUÉS del INSERT en `auth.users`
- **Problema potencial:** El trigger puede estar:
  - Leyendo `raw_user_meta_data` INCORRECTAMENTE
  - Sobrescribiendo los valores que el RPC ya guardó
  - No extrayendo correctamente `lat`, `lon`, `address_structured`
- **Acción:** 🔍 **AUDITAR EL TRIGGER**

### **Hipótesis 3: Conflicto de orden de ejecución**
- **Flujo actual:**
  1. Flutter llama `signUp()` → crea usuario en `auth.users`
  2. Trigger `handle_new_user_signup_v2()` se dispara automáticamente
  3. Flutter llama `ensure_user_profile_public()` RPC
- **Problema:** El RPC puede estar ejecutándose DESPUÉS del trigger, pero:
  - El trigger ya creó el registro con valores NULL
  - El RPC hace UPDATE, pero usa `COALESCE()` que mantiene valores existentes
- **Acción:** 🔍 **VERIFICAR ORDEN DE EJECUCIÓN**

---

## 📋 PLAN DE ACCIÓN QUIRÚRGICA

### **FASE 1: AUDITORÍA (NO TOCAR NADA AÚN)**

#### ✅ Paso 1: Verificar logs de Supabase
```
Dashboard > Database > Logs > Buscar "DEBUG"
```
**Objetivo:** Confirmar que `ensure_user_profile_public()` está recibiendo los datos correctamente

#### ✅ Paso 2: Ejecutar script de auditoría SQL
**Archivo:** `AUDITORIA_TRIGGER_Y_RPC.sql`
**Objetivo:** 
- Ver el código actual del TRIGGER `handle_new_user_signup_v2()`
- Ver el código actual del RPC `ensure_user_profile_public()`
- Verificar que no haya otros triggers interfiriendo

---

### **FASE 2: IDENTIFICAR EL PROBLEMA**

Después de ejecutar la auditoría, analizaremos:

1. **Si el trigger NO está extrayendo `raw_user_meta_data` correctamente:**
   - ✅ Reparar el trigger para que lea `lat`, `lon`, `address_structured`
   
2. **Si el RPC está usando `COALESCE()` incorrectamente:**
   - ✅ Cambiar `COALESCE(p_lat, lat)` por solo `p_lat` en INSERT
   - ✅ Mantener `COALESCE()` solo en UPDATE
   
3. **Si hay conflicto de orden:**
   - ✅ Hacer que el trigger lea `raw_user_meta_data` CORRECTAMENTE
   - ✅ Hacer que el RPC NO use `COALESCE()` en INSERT inicial

---

### **FASE 3: REPARACIÓN QUIRÚRGICA**

Una vez identificado el problema, crearemos UN SOLO script SQL que:

1. ✅ **Repara SOLO lo necesario** (trigger O RPC, no ambos)
2. ✅ **NO toca funciones de `restaurant` o `delivery_agent`**
3. ✅ **Mantiene toda la lógica funcional existente**
4. ✅ **Agrega logs de debug para verificación**

---

## 🎯 PRÓXIMOS PASOS

### **AHORA:**
1. Ejecuta el script `AUDITORIA_TRIGGER_Y_RPC.sql` en Supabase
2. Copia y pega aquí el OUTPUT completo
3. Con esa información, crearemos el script de reparación quirúrgica

### **DESPUÉS (tras la auditoría):**
1. Crear script `FIX_CLIENT_REGISTRATION_FINAL.sql`
2. Ejecutar el fix
3. Hacer un nuevo registro de cliente desde Flutter
4. Verificar que TODO se guarde correctamente

---

## 📝 NOTAS IMPORTANTES

- ⚠️ **NO ejecutar ningún script de reparación aún**
- ⚠️ **PRIMERO necesitamos ver el código actual del trigger**
- ⚠️ **El problema puede estar en el trigger, NO en el RPC**
- ✅ **Los logs de Flutter confirman que los datos SÍ se envían**
- ✅ **El RPC tiene logs agregados, revisar Dashboard > Logs**

---

## 🔗 ARCHIVOS RELACIONADOS

- **Flutter:** `/lib/screens/auth/register_screen.dart` (líneas 194-224)
- **Supabase Config:** `/lib/supabase/supabase_config.dart` (líneas 161-274)
- **RPC actual:** `RESTAURAR_ENSURE_USER_PROFILE_CON_LOGS.sql`
- **Schema:** `DATABASE_SCHEMA.sql`

---

**🎯 OBJETIVO FINAL:**
Que cuando un cliente se registre, TODOS estos datos se guarden correctamente:
- `users.name` ✅
- `users.phone` ✅
- `client_profiles.address` ✅
- `client_profiles.lat` ✅
- `client_profiles.lon` ✅
- `client_profiles.address_structured` ✅
