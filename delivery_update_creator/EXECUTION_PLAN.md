# 🚀 DELIVERY AGENT & RESTAURANT REGISTRATION FIX

## ⚠️ IMPORTANTE: SOLO DELIVERY_AGENT Y RESTAURANT

**Este plan NO modifica el registro de clientes (client), que ya funciona correctamente.**

---

## 📦 UBICACIÓN DE ARCHIVOS

Todos los archivos SQL están en:
```
/hologram/data/workspace/project/delivery_update_creator/
```

---

## 🎯 PLAN DE EJECUCIÓN

### **FASE 1: BACKEND (SUPABASE SQL) - 4 SCRIPTS**

Ejecuta estos scripts **EN ORDEN** en Supabase SQL Editor:

#### **1️⃣ PASO 1: Crear RPCs de Registro**
```
📁 delivery_update_creator/01_create_registration_rpcs.sql
```

**QUÉ HACE:**
- ✅ Crea `register_delivery_agent_v2()` con rol `'delivery_agent'`
- ✅ Crea `register_restaurant_v2()` con rol `'restaurant'`
- ⚠️ **NO TOCA** el registro de clientes (ya funciona)

**TIEMPO ESTIMADO:** 30 segundos

**RESULTADO ESPERADO:**
```sql
✅ register_delivery_agent_v2() created (role: delivery_agent)
✅ register_restaurant_v2() created (role: restaurant)
⚠️  CLIENT registration NOT MODIFIED (already working)
```

---

#### **2️⃣ PASO 2: Agregar Campos de Status**
```
📁 delivery_update_creator/02_add_status_fields.sql
```

**QUÉ HACE:**
- ✅ Agrega columna `status` a `delivery_profiles`
- ✅ Agrega columna `status` a `restaurant_profiles`
- ✅ Actualiza registros existentes con status por defecto
- ⚠️ **NO TOCA** `client_profiles` (ya funciona)

**TIEMPO ESTIMADO:** 30 segundos

**RESULTADO ESPERADO:**
```sql
✅ Step 2 Complete: Status fields verified
delivery_profiles.status: ✅ EXISTS
restaurant_profiles.status: ✅ EXISTS
⚠️  client_profiles NOT MODIFIED (already working)
```

**NOTA:** Este paso soluciona el error: `"record 'old' has no field 'status'"`

---

#### **3️⃣ PASO 3: Actualizar Trigger de Signup**
```
📁 delivery_update_creator/03_update_master_handle_signup.sql
```

**QUÉ HACE:**
- ✅ Elimina todas las versiones anteriores de `master_handle_signup()`
- ✅ Recrea el trigger con soporte completo para:
  - Rol `'delivery_agent'` → crea `delivery_profiles` con vehicle_type/license_plate
  - Rol `'restaurant'` → crea `restaurant_profiles` con restaurant_name/address
  - ⚠️ Rol `'client'` → **NO SE MODIFICA** (el caso ya existente se mantiene)
  - Rol `'admin'` → solo crea `users`
- ✅ Elimina todas las referencias a `OLD.status`

**TIEMPO ESTIMADO:** 45 segundos

**RESULTADO ESPERADO:**
```sql
✅ Step 3 Complete: master_handle_signup recreated
Trigger status: ✅ ACTIVE
Updated roles: delivery_agent, restaurant
Status field handling: ✅ FIXED (no OLD.status references)
⚠️  CLIENT case NOT MODIFIED (already working)
```

---

#### **4️⃣ PASO 4: Verificar Configuración**
```
📁 delivery_update_creator/04_verify_setup.sql
```

**QUÉ HACE:**
- ✅ Verifica que los 2 RPCs existan (delivery_agent y restaurant)
- ✅ Verifica que `master_handle_signup()` exista (solo 1 versión)
- ✅ Verifica que el trigger esté activo en `auth.users`
- ✅ Verifica que las columnas `status` existan en delivery_profiles y restaurant_profiles
- ✅ Verifica campos de vehículo en `delivery_profiles`
- ✅ Verifica campos de restaurante en `restaurant_profiles`
- ⚠️ **NO VERIFICA** client_profiles (ya funciona)

**TIEMPO ESTIMADO:** 15 segundos

**RESULTADO ESPERADO:**
```sql
========================================
1. REGISTRATION RPCs
========================================
Found 2 registration functions (expected: 2)
✅ register_delivery_agent_v2
✅ register_restaurant_v2
⚠️  register_client NOT CHECKED (already working)

========================================
2. SIGNUP TRIGGER FUNCTION
========================================
Found 1 master_handle_signup functions (expected: 1)
✅ master_handle_signup (single version)

========================================
3. TRIGGER ATTACHMENT
========================================
✅ Trigger "on_auth_user_created" is active on auth.users

========================================
4. STATUS COLUMNS
========================================
delivery_profiles.status: ✅
restaurant_profiles.status: ✅
⚠️  client_profiles NOT CHECKED (already working)

========================================
5. DELIVERY AGENT FIELDS
========================================
delivery_profiles.vehicle_type: ✅
delivery_profiles.license_plate: ✅

========================================
6. RESTAURANT FIELDS
========================================
restaurant_profiles.restaurant_name: ✅
restaurant_profiles.restaurant_address: ✅
restaurant_profiles.lat: ✅
restaurant_profiles.lon: ✅

========================================
✅ VERIFICATION COMPLETE
========================================
⚠️  CLIENT registration NOT MODIFIED (already working)
```

**⚠️ IMPORTANTE:** Si ves algún ❌ o ⚠️, vuelve a ejecutar el script correspondiente.

---

### **FASE 2: FRONTEND (FLUTTER) - SOLO 2 ARCHIVOS**

Una vez completada la Fase 1, los siguientes archivos Flutter serán actualizados:

#### **Archivos a Modificar:**

1. **`lib/screens/public/delivery_agent_registration_screen.dart`**
   - Cambiar rol: `'repartidor'` → `'delivery_agent'`
   - Cambiar RPC: `register_restaurant_v2` → `register_delivery_agent_v2`
   - Pasar parámetros correctos: `vehicle_type`, `license_plate`

2. **`lib/screens/public/restaurant_registration_screen.dart`**
   - Cambiar rol: `'restaurante'` → `'restaurant'` (si aplica)
   - Usar RPC correcto: `register_restaurant_v2`
   - Pasar parámetros correctos: `restaurant_name`, `restaurant_address`

⚠️ **`lib/screens/auth/register_screen.dart` NO SE MODIFICA** (clientes ya funcionan correctamente)

---

## 📊 RESUMEN COMPLETO

| Fase | Tipo | Archivos | Descripción |
|------|------|----------|-------------|
| **1** | SQL | `01_create_registration_rpcs.sql` | Crea 2 funciones RPC: delivery_agent y restaurant |
| **1** | SQL | `02_add_status_fields.sql` | Agrega columnas `status` a delivery_profiles y restaurant_profiles |
| **1** | SQL | `03_update_master_handle_signup.sql` | Recrea trigger de signup SOLO para delivery_agent y restaurant |
| **1** | SQL | `04_verify_setup.sql` | Verifica que todo esté configurado correctamente |
| **2** | Flutter | `delivery_agent_registration_screen.dart` | Actualiza rol y RPC para delivery agents |
| **2** | Flutter | `restaurant_registration_screen.dart` | Actualiza rol y RPC para restaurants |
| - | - | **register_screen.dart** | **NO SE MODIFICA** (clientes ya funcionan) |

---

## ✅ CRITERIOS DE ÉXITO

Después de ejecutar todos los scripts, deberías poder:

1. ✅ **Registrar un delivery agent** con rol `'delivery_agent'`
2. ✅ **Registrar un restaurante** con rol `'restaurant'`
3. ✅ **Email de verificación** funciona correctamente para ambos roles
4. ✅ **Sin errores** de "record 'old' has no field 'status'"
5. ✅ **Profiles se crean** automáticamente con status correcto (`pending_approval`)
6. ✅ **vehicle_type/license_plate** se guardan en delivery_profiles
7. ✅ **restaurant_name/restaurant_address** se guardan en restaurant_profiles
8. ⚠️ **Clientes siguen funcionando** como antes (sin cambios)

---

## 🆘 TROUBLESHOOTING

### **❌ Error: "function already exists"**
**Solución:** El script 01 ya limpia versiones anteriores. Si persiste, ejecuta manualmente:
```sql
DROP FUNCTION IF EXISTS public.register_delivery_agent_v2 CASCADE;
DROP FUNCTION IF EXISTS public.register_restaurant_v2 CASCADE;
DROP FUNCTION IF EXISTS public.register_client_v2 CASCADE;
```
Luego vuelve a ejecutar el script 01.

---

### **❌ Error: "column status already exists"**
**Solución:** El script 02 verifica si existe antes de crear. Este mensaje es normal si ya existe.

---

### **❌ Error: "trigger already exists"**
**Solución:** El script 03 ya elimina el trigger anterior. Si persiste, ejecuta manualmente:
```sql
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users CASCADE;
```
Luego vuelve a ejecutar el script 03.

---

### **❌ Verificación muestra ❌ en alguna sección**
**Solución:** 
- Si faltan RPCs → Re-ejecuta `01_create_registration_rpcs.sql`
- Si falta status → Re-ejecuta `02_add_status_fields.sql`
- Si falta trigger → Re-ejecuta `03_update_master_handle_signup.sql`

---

## 🚀 SIGUIENTE PASO

Una vez completada la **Fase 1 (SQL)**, confirma que el script 04 muestra todo en ✅, luego procederemos con la **Fase 2 (Flutter)**.

---

**NOTA IMPORTANTE:** Copia TODO el output de cada script (incluidos los mensajes NOTICE) para verificar que se ejecutaron correctamente.
