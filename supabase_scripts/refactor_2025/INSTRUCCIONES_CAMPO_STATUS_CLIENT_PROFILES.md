# 📋 INSTRUCCIONES: Agregar campo `status` a `client_profiles`

---

## 🎯 OBJETIVO

Agregar el campo `status` a la tabla `client_profiles` para permitir la gestión del estado de los perfiles de clientes (activo, inactivo, suspendido).

---

## 📊 CONTEXTO

### **Problema identificado:**

La tabla `client_profiles` **NO tiene** el campo `status`, pero los RPCs de registro intentan insertarlo, causando errores:

```sql
-- ❌ ESTADO ACTUAL (DATABASE_SCHEMA.sql):
CREATE TABLE public.client_profiles (
  user_id uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  address text,
  lat double precision,
  lon double precision,
  address_structured jsonb,
  average_rating numeric DEFAULT 0.00,
  total_reviews integer DEFAULT 0,
  profile_image_url text,
  -- ❌ FALTA: status
);
```

### **Error causado:**

```
POST /auth/v1/signup 500 (Internal Server Error)
{"code":"unexpected_failure","message":"Database error saving new user"}
```

### **Comparación con otras tablas:**

| Tabla | Campo `status` | Valores posibles |
|-------|---------------|------------------|
| `restaurants` | ✅ Sí | 'pending', 'approved', 'rejected' |
| `delivery_agent_profiles` | ✅ Sí | 'pending', 'approved', 'rejected', 'blocked' |
| `client_profiles` | ❌ **NO** | **(DEBE AGREGARSE)** |

---

## ✅ SOLUCIÓN PROPUESTA

Agregar el campo `status` a `client_profiles` con:
- **Valores permitidos:** 'active', 'inactive', 'suspended'
- **Valor por defecto:** 'active'
- **Constraint CHECK** para validar valores
- **Índice** para optimizar búsquedas por status

---

## 📝 SCRIPTS CREADOS

### **1. Script de migración de tabla**

**Archivo:** `supabase_scripts/refactor_2025/12_add_status_to_client_profiles.sql`

**Funciones:**
- ✅ Agrega columna `status` con constraint CHECK
- ✅ Crea índice `idx_client_profiles_status`
- ✅ Actualiza registros existentes a 'active'
- ✅ Verifica la estructura actualizada

---

### **2. Script de actualización de RPCs**

**Archivo:** `supabase_scripts/refactor_2025/13_update_client_registration_rpc.sql`

**Funciones:**
- ✅ Actualiza `ensure_client_profile_and_account()` para insertar `status='active'`
- ✅ Actualiza trigger `handle_new_user()` para crear perfiles con status
- ✅ Verifica que todo esté correcto

---

## 🚀 INSTRUCCIONES DE EJECUCIÓN

### **PASO 1: Backup de seguridad (OPCIONAL pero recomendado)**

```sql
-- En Supabase SQL Editor:
CREATE TABLE IF NOT EXISTS backup_refactor_2025.client_profiles_before_status AS 
SELECT * FROM public.client_profiles;
```

---

### **PASO 2: Ejecutar script de migración de tabla**

1. **Abrir:** Supabase Dashboard > SQL Editor
2. **Copiar y pegar:** Contenido de `12_add_status_to_client_profiles.sql`
3. **Ejecutar** (Run)
4. **Verificar resultado:**

```
[OK] Columna status existe en client_profiles
[OK] Total de client_profiles: X
[INFO] Distribucion por status:
  - active: X registros
```

---

### **PASO 3: Ejecutar script de actualización de RPCs**

1. **Abrir:** Supabase Dashboard > SQL Editor
2. **Copiar y pegar:** Contenido de `13_update_client_registration_rpc.sql`
3. **Ejecutar** (Run)
4. **Verificar resultado:**

```
[OK] Funcion ensure_client_profile_and_account existe
[OK] Trigger on_auth_user_created existe
[OK] Columna status existe en client_profiles
[SUCCESS] Sistema de registro de cliente actualizado correctamente
```

---

### **PASO 4: Probar registro de nuevo usuario**

1. **En tu app Flutter:**
   - Ir a pantalla de registro
   - Crear nuevo usuario con email/password
   - **Resultado esperado:** ✅ Registro exitoso sin error 500

2. **Verificar en Supabase:**

```sql
-- Verificar que el usuario se creó correctamente:
SELECT 
  u.id,
  u.email,
  u.name,
  u.role,
  cp.status,
  cp.created_at
FROM public.users u
INNER JOIN public.client_profiles cp ON u.id = cp.user_id
WHERE u.email = 'tu_email_de_prueba@example.com';

-- ✅ RESULTADO ESPERADO:
-- status = 'active'
```

---

## 🔍 VERIFICACIÓN POST-MIGRACIÓN

### **1. Verificar estructura de tabla**

```sql
SELECT 
  column_name,
  data_type,
  column_default,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'client_profiles'
ORDER BY ordinal_position;

-- ✅ DEBE APARECER:
-- status | text | 'active' | NO
```

---

### **2. Verificar constraint CHECK**

```sql
SELECT 
  conname AS constraint_name,
  pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.client_profiles'::regclass
AND contype = 'c';

-- ✅ DEBE APARECER:
-- CHECK (status IN ('active', 'inactive', 'suspended'))
```

---

### **3. Verificar índice**

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'client_profiles'
AND indexname = 'idx_client_profiles_status';

-- ✅ DEBE APARECER:
-- CREATE INDEX idx_client_profiles_status ON public.client_profiles USING btree (status)
```

---

### **4. Verificar función RPC**

```sql
SELECT 
  proname AS function_name,
  pg_get_functiondef(oid) AS definition
FROM pg_proc
WHERE proname = 'ensure_client_profile_and_account';

-- ✅ DEBE CONTENER:
-- INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
-- VALUES (p_user_id, 'active', v_now, v_now)
```

---

## 🎯 NUEVA ESTRUCTURA FINAL

### **Tabla `client_profiles` ACTUALIZADA:**

```sql
CREATE TABLE public.client_profiles (
  user_id uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),  -- ✅ NUEVO
  address text,
  lat double precision,
  lon double precision,
  address_structured jsonb,
  average_rating numeric DEFAULT 0.00,
  total_reviews integer DEFAULT 0,
  profile_image_url text,
  CONSTRAINT client_profiles_pkey PRIMARY KEY (user_id),
  CONSTRAINT client_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);

-- Índice para búsquedas por status
CREATE INDEX idx_client_profiles_status ON public.client_profiles(status);
```

---

## 🔄 PROCESO DE REGISTRO ACTUALIZADO

### **Flujo completo:**

```
1. Usuario se registra con email/password
   ↓
2. Supabase Auth crea registro en auth.users
   ↓
3. Trigger on_auth_user_created se ejecuta
   ↓
4. Función handle_new_user() ejecuta:
   a. Crea registro en public.users (role='client')
   b. Llama a ensure_client_profile_and_account()
      - Crea client_profiles con status='active'  ✅ NUEVO
      - Crea accounts con account_type='client'
   ↓
5. ✅ Usuario listo con perfil activo
```

---

## 📌 VALORES DEL CAMPO `status`

| Valor | Descripción | Uso |
|-------|-------------|-----|
| `'active'` | Perfil activo (por defecto) | Usuario puede usar la app normalmente |
| `'inactive'` | Perfil inactivo | Usuario desactivó su cuenta temporalmente |
| `'suspended'` | Perfil suspendido | Admin bloqueó al usuario por violación de términos |

---

## 🛡️ SEGURIDAD Y VALIDACIONES

### **1. Constraint CHECK a nivel de base de datos:**

```sql
CHECK (status IN ('active', 'inactive', 'suspended'))
```

**Previene:** Insertar valores inválidos como 'deleted', 'banned', etc.

---

### **2. Valor por defecto:**

```sql
DEFAULT 'active'
```

**Garantiza:** Todos los nuevos registros tienen status válido automáticamente.

---

### **3. NOT NULL:**

```sql
status text NOT NULL
```

**Garantiza:** El campo nunca puede ser NULL.

---

## 🔧 QUERIES ÚTILES POST-MIGRACIÓN

### **1. Listar todos los clientes por status:**

```sql
SELECT 
  u.email,
  u.name,
  cp.status,
  cp.created_at
FROM public.users u
INNER JOIN public.client_profiles cp ON u.id = cp.user_id
WHERE u.role = 'client'
ORDER BY cp.status, u.email;
```

---

### **2. Contar clientes por status:**

```sql
SELECT 
  status,
  COUNT(*) as total
FROM public.client_profiles
GROUP BY status
ORDER BY status;
```

---

### **3. Suspender un cliente (solo admin):**

```sql
UPDATE public.client_profiles
SET 
  status = 'suspended',
  updated_at = now()
WHERE user_id = 'uuid-del-usuario';
```

---

### **4. Reactivar un cliente:**

```sql
UPDATE public.client_profiles
SET 
  status = 'active',
  updated_at = now()
WHERE user_id = 'uuid-del-usuario';
```

---

## ⚠️ NOTAS IMPORTANTES

1. **Prerequisito:** Ejecutar `12_add_status_to_client_profiles.sql` ANTES de `13_update_client_registration_rpc.sql`

2. **Registros existentes:** Todos los `client_profiles` existentes se actualizarán automáticamente a `status='active'`

3. **Compatibilidad:** Los cambios son **retrocompatibles** - no rompen queries existentes

4. **RLS Policies:** No se modifican las políticas RLS existentes

5. **Testing:** Probar el registro de nuevos usuarios DESPUÉS de ejecutar ambos scripts

---

## 🚨 ROLLBACK (si algo sale mal)

### **Si necesitas revertir los cambios:**

```sql
-- 1. Remover columna status
ALTER TABLE public.client_profiles
DROP COLUMN IF EXISTS status;

-- 2. Remover índice
DROP INDEX IF EXISTS public.idx_client_profiles_status;

-- 3. Restaurar función anterior (si guardaste backup)
-- (Ejecutar versión anterior de ensure_client_profile_and_account)
```

---

## ✅ CHECKLIST FINAL

Marca cada paso después de completarlo:

- [ ] **PASO 1:** Backup de `client_profiles` (opcional)
- [ ] **PASO 2:** Ejecutar `12_add_status_to_client_profiles.sql`
  - [ ] Verificar mensaje: `[OK] Columna status existe`
- [ ] **PASO 3:** Ejecutar `13_update_client_registration_rpc.sql`
  - [ ] Verificar mensaje: `[SUCCESS] Sistema de registro actualizado`
- [ ] **PASO 4:** Probar registro de nuevo usuario en Flutter
  - [ ] Usuario se crea sin error 500
  - [ ] Verificar en Supabase que `status='active'`
- [ ] **PASO 5:** Verificar estructura final con queries de verificación

---

## 📞 SOPORTE

Si encuentras algún error durante la ejecución:

1. **Revisar logs de Supabase:** Dashboard > Database > Logs
2. **Verificar permisos:** El usuario debe tener permisos de ALTER TABLE
3. **Ejecutar queries de verificación** de la sección "Verificación Post-Migración"

---

## 📄 RESUMEN EJECUTIVO

### **Scripts creados:**
1. `12_add_status_to_client_profiles.sql` - Agrega campo `status` a la tabla
2. `13_update_client_registration_rpc.sql` - Actualiza RPCs para usar `status`

### **Tiempo estimado de ejecución:**
- Script 1: ~1-2 segundos
- Script 2: ~2-3 segundos
- **Total:** < 5 segundos

### **Impacto:**
- ✅ Sin downtime
- ✅ Retrocompatible
- ✅ Registros existentes actualizados automáticamente

### **Resultado esperado:**
✅ Registro de nuevos usuarios funciona correctamente sin error 500
✅ Todos los `client_profiles` tienen `status='active'`
✅ Sistema listo para gestionar estados de perfiles (activo/inactivo/suspendido)

---

**¡Listo para ejecutar!** 🚀
