# 🔧 Plan de Solución: Registro de Delivery Agents

## 📊 DIAGNÓSTICO COMPLETO

### Console Log Analizado:
```
🚀 Starting signup process for: walfre.am@gmail.com
✅ User registered in auth.users successfully
📧 User needs email verification: true
📝 Ensuring user profile using RPC...
🛡️ ensure_user_profile_public result: {data: {user_id: 651982b3-2d19-42dc-bcf0-45f6f6abe6cb}, ...}
❌ ensureFinancialAccount error: PostgrestException(
    message: function public.ensure_delivery_agent_role_and_profile(uuid) does not exist,
    code: 42883
)
```

### 🔍 Problema Identificado:

Tu app tiene **DOS pantallas** de registro de delivery agents:

1. **`/nuevo-repartidor` (delivery_signup_screen.dart)** → Registro simple (email, nombre, teléfono, password)
2. **`/registro-repartidor` (delivery_agent_registration_screen.dart)** → Registro completo (documentos, vehículo, etc.)

#### Flujo Actual en `delivery_signup_screen.dart`:
```
1. ✅ Crear auth.user
2. ✅ Crear public.users vía ensure_user_profile_public()
3. ❌ Llamar a ensureFinancialAccount()
   └─> Intenta insertar en table 'accounts'
   └─> TRIGGER se dispara: handle_delivery_agent_account_insert()
   └─> Llama a ensure_delivery_agent_role_and_profile()
   └─> ❌ FUNCIÓN NO EXISTE O TIENE ENUM VALUES INCORRECTOS
```

#### ¿Por qué falla?

El **TRIGGER** `trg_handle_delivery_agent_account_insert` se dispara automáticamente cuando se inserta un registro en `accounts` con `account_type = 'delivery_agent'`.

Este trigger llama a la función `ensure_delivery_agent_role_and_profile()` que:
- ❌ **NO EXISTE** en tu database actual, o
- ❌ Usa valores de enum **INCORRECTOS** (`'pending_verification'` en lugar de `'pending'`)

---

## ✅ SOLUCIÓN

### Estrategia:

**Crear/actualizar la función `ensure_delivery_agent_role_and_profile()`** para que:
1. ✅ Use sintaxis PostgreSQL correcta
2. ✅ Use valores de enum correctos según `DATABASE_SCHEMA.sql`
3. ✅ Cree registro mínimo en `delivery_agent_profiles`
4. ✅ Cree registro en `user_preferences`
5. ✅ Actualice el role a `'delivery_agent'` en `public.users`

De esta forma, cuando `delivery_signup_screen.dart` llame a `ensureFinancialAccount()`:
- ✅ Se inserta el registro en `accounts`
- ✅ El trigger se dispara
- ✅ La función crea el perfil mínimo de delivery agent
- ✅ El usuario puede completar su perfil dentro de la app

---

## 📁 ARCHIVOS CREADOS

### SQL Script:
**`FIX_DELIVERY_AGENT_TRIGGER_COMPLETE.sql`** ⚡ **← EJECUTA ESTE**
- Recrea la función `ensure_delivery_agent_role_and_profile()` con sintaxis correcta
- Recrea los triggers en la tabla `accounts`
- Hace backfill de registros existentes que no tienen perfil
- **LISTO PARA COPIAR Y PEGAR EN SUPABASE**

---

## 🚀 INSTRUCCIONES DE EJECUCIÓN

### Paso 1: Ejecutar Script SQL ⚡
1. Abre **Supabase SQL Editor**
2. Copia TODO el contenido de `FIX_DELIVERY_AGENT_TRIGGER_COMPLETE.sql`
3. Pega y ejecuta
4. Verifica que no haya errores

### Paso 2: Hot Restart 🔄
1. En Dreamflow Preview Panel
2. Click en botón **Hot Restart** (o Refresh)

### Paso 3: Probar Registro 🧪
1. Navega a `/nuevo-repartidor` en tu app
2. Llena el formulario:
   - Nombre
   - Email
   - Teléfono
   - Contraseña
3. Submit
4. ✅ Debería crear:
   - `auth.users` ✅
   - `public.users` ✅
   - `accounts` ✅
   - `delivery_agent_profiles` ✅ (perfil mínimo)
   - `user_preferences` ✅

### Paso 4: Verificar en Supabase 🔍
Ejecuta esta query para verificar:
```sql
SELECT 
  u.id,
  u.email,
  u.name,
  u.role,
  a.account_type,
  a.balance,
  dap.status,
  dap.account_state,
  up.has_seen_onboarding
FROM public.users u
LEFT JOIN public.accounts a ON a.user_id = u.id
LEFT JOIN public.delivery_agent_profiles dap ON dap.user_id = u.id
LEFT JOIN public.user_preferences up ON up.user_id = u.id
WHERE u.email = 'walfre.am@gmail.com'
ORDER BY u.created_at DESC
LIMIT 1;
```

**Resultado Esperado:**
| Campo | Valor Esperado |
|-------|----------------|
| role | `delivery_agent` |
| account_type | `delivery_agent` |
| balance | `0.00` |
| status | `pending` |
| account_state | `pending` |
| has_seen_onboarding | `false` |

---

## 📋 TABLAS AFECTADAS

### Antes del Fix:
```
✅ auth.users (creado)
✅ public.users (creado)
❌ accounts (NO creado - trigger falla)
❌ delivery_agent_profiles (NO creado)
❌ user_preferences (NO creado)
```

### Después del Fix:
```
✅ auth.users (creado)
✅ public.users (creado)
✅ accounts (creado - trigger funciona)
✅ delivery_agent_profiles (creado por trigger)
✅ user_preferences (creado por trigger)
```

---

## 🎯 VALIDACIÓN FINAL

Después de ejecutar el script, prueba estos casos:

### ✅ Caso 1: Nuevo Usuario desde /nuevo-repartidor
- Registrar nuevo delivery agent
- Verificar que se crean TODOS los registros
- No debe haber errores en console

### ✅ Caso 2: Usuario Existente (Backfill)
- Usuarios existentes con `account_type = 'delivery_agent'` sin perfil
- El script automáticamente crea sus perfiles

### ✅ Caso 3: Login después del registro
- Usuario verifica su email
- Inicia sesión
- Debe ver su dashboard de delivery agent correctamente

---

## 🔍 TROUBLESHOOTING

### Si sigue fallando:

1. **Verificar que el script corrió sin errores:**
   ```sql
   SELECT proname, prosrc 
   FROM pg_proc 
   WHERE proname = 'ensure_delivery_agent_role_and_profile';
   ```
   Debería retornar 1 fila

2. **Verificar que los triggers existen:**
   ```sql
   SELECT trigger_name, event_manipulation, event_object_table
   FROM information_schema.triggers
   WHERE trigger_name LIKE '%delivery_agent%';
   ```
   Deberías ver:
   - `trg_handle_delivery_agent_account_insert` (INSERT)
   - `trg_handle_delivery_agent_account_update` (UPDATE)

3. **Verificar valores de enum:**
   ```sql
   SELECT enumlabel 
   FROM pg_enum 
   WHERE enumtypid = 'delivery_agent_status'::regtype;
   ```
   Debería incluir: `pending`, `active`, etc.

4. **Ver logs de errores:**
   ```sql
   SELECT * FROM public.function_logs 
   WHERE function_name LIKE '%delivery%' 
   ORDER BY created_at DESC 
   LIMIT 10;
   ```

---

## 📌 NOTAS IMPORTANTES

### ⚠️ NO modificar código Flutter
El código de `delivery_signup_screen.dart` **NO necesita cambios**. La solución es 100% SQL.

### ⚠️ Dos flujos de registro
Tu app mantiene dos flujos:
1. **Simple** (`/nuevo-repartidor`): Email + Password → Completa perfil dentro de la app
2. **Completo** (`/registro-repartidor`): Todo de una vez → Llama a `register_delivery_agent_atomic()`

Ambos flujos funcionarán correctamente después del fix.

### ✅ Idempotente
El script es seguro para ejecutar múltiples veces. Usa `CREATE OR REPLACE` y `ON CONFLICT DO NOTHING`.

---

## 🎉 RESULTADO ESPERADO

Después del fix, cuando un usuario se registre desde `/nuevo-repartidor`:

1. ✅ Usuario creado en `auth.users`
2. ✅ Perfil básico creado en `public.users`
3. ✅ Cuenta financiera creada en `accounts`
4. ✅ **TRIGGER se dispara automáticamente** ⚡
5. ✅ Perfil mínimo creado en `delivery_agent_profiles`
6. ✅ Preferencias creadas en `user_preferences`
7. ✅ Role actualizado a `'delivery_agent'`
8. ✅ Usuario recibe email de verificación
9. ✅ Puede iniciar sesión y completar su perfil

**Sin errores, sin llamadas manuales adicionales, todo automático** 🚀
