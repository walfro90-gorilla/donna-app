# 🎯 PLAN MASTER: REFACTORIZACIÓN PROFESIONAL DE SIGNUP

---

## 📊 RESUMEN EJECUTIVO

**Problema actual:** El signup devuelve error 500 porque existe una función `handle_new_user()` que se ejecuta en un trigger sobre `auth.users`, pero está fallando silenciosamente sin logs.

**Diagnóstico completo:**
- ✅ Auditoría de 180+ funciones SQL relacionadas con signup/profiles
- ✅ Auditoría de 18 triggers activos en el sistema
- ✅ Auditoría de 60+ RPCs públicos expuestos
- ✅ Verificación del schema: Foreign keys correctas (`users.id → auth.users.id`, `profiles.user_id → users.id`)

**Objetivo:** Crear un flujo de signup **atómico, robusto y profesional** que maneje cliente, restaurante y repartidor con rollback automático en caso de falla.

---

## 🔍 HALLAZGOS CLAVE DE LA AUDITORÍA

### **1. FUNCIÓN PRINCIPAL DE SIGNUP**
La función `handle_new_user()` existe y es la responsable de crear perfiles:

```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_email TEXT;
  v_role TEXT := 'cliente'; -- Por defecto todos son clientes
BEGIN
  -- Obtener email del nuevo usuario en auth.users
  v_email := NEW.email;
  
  -- Log de inicio
  INSERT INTO public.debug_user_signup_log (...) VALUES (...);

  -- PASO 1: Insertar en public.users
  INSERT INTO public.users (id, email, role, name, created_at, updated_at, email_confirm)
  VALUES (NEW.id, v_email, v_role, COALESCE(NEW.raw_user_meta_data->>'name', v_email), now(), now(), false)
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email, updated_at = now();

  -- PASO 2: Crear client_profile
  INSERT INTO public.client_profiles (user_id, created_at, updated_at)
  VALUES (NEW.id, now(), now())
  ON CONFLICT (user_id) DO UPDATE SET updated_at = now();

  -- PASO 3: Crear cuenta (account) para el cliente
  INSERT INTO public.accounts (id, user_id, account_type, balance, created_at, updated_at)
  VALUES (uuid_generate_v4(), NEW.id, 'client', 0.00, now(), now())
  ON CONFLICT DO NOTHING;

  -- PASO 4: Crear user_preferences
  INSERT INTO public.user_preferences (user_id, created_at, updated_at)
  VALUES (NEW.id, now(), now())
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    INSERT INTO public.debug_user_signup_log (...) VALUES (...);
    RAISE;
END;
$function$
```

**Problema:** Esta función asume que TODOS los signups son clientes (`v_role := 'cliente'`), lo cual es incorrecto. No maneja restaurantes ni repartidores adecuadamente.

---

### **2. TRIGGERS CRÍTICOS ENCONTRADOS**

De la auditoría de triggers, encontramos **18 funciones trigger activas**, incluyendo:

- `handle_new_user()` → Ejecutada en `auth.users` (AFTER INSERT)
- `trg_users_normalize_role()` → Normaliza roles en `public.users` (BEFORE INSERT/UPDATE)
- `audit_delivery_agent_insert()` → **BLOQUEA** inserciones en `delivery_agent_profiles` si el rol NO es 'repartidor'
- `delivery_agent_profiles_guard()` → Otro guardia que previene inserciones incorrectas
- `create_account_on_user_approval()` → Crea `accounts` cuando `users.status` cambia a 'approved'
- `fn_notify_admin_on_new_*()` → Notificaciones de admin (cliente, repartidor, restaurante)

**Problema crítico:** Múltiples triggers que intentan hacer lo mismo, creando conflictos y lógica redundante.

---

### **3. RPCs EXPUESTOS (60+)**

Encontramos **múltiples RPCs públicos** para signup que NO deberían existir o están obsoletos:

- `register_client()` ❌ Redundante
- `register_delivery_agent()` ❌ Redundante
- `register_delivery_agent_atomic()` ❌ Redundante
- `register_restaurant()` ❌ Redundante
- `register_restaurant_v2()` ❌ Redundante (duplicado)
- `create_user_profile_public()` ❌ Redundante (2 versiones)
- `create_delivery_agent()` ❌ Redundante
- `create_restaurant_public()` ❌ Redundante
- `ensure_user_profile_public()` ❌ Redundante
- `ensure_user_profile_v2()` ❌ Redundante
- `ensure_client_profile_and_account()` ❌ Redundante
- `ensure_delivery_agent_role_and_profile()` ❌ Redundante
- `ensure_my_delivery_profile()` ❌ Redundante

**Problema:** Demasiadas funciones públicas que intentan hacer signup desde Flutter, cuando debería ser automático vía el trigger en `auth.users`.

---

### **4. FOREIGN KEYS VERIFICADAS** ✅

El schema está correctamente estructurado:

```
auth.users (id)
    ↓
public.users (id references auth.users.id) ✅
    ↓
    ├── public.client_profiles (user_id references users.id) ✅
    ├── public.delivery_agent_profiles (user_id references users.id) ✅
    └── public.restaurants (user_id references users.id) ✅
```

**Conclusión:** El schema es sólido. El problema está en la lógica de las funciones y triggers.

---

## 🏗️ ARQUITECTURA NUEVA (PROFESIONAL Y QUIRÚRGICA)

### **FLUJO DE SIGNUP**

```
┌─────────────────────────────────────────────────────────────────┐
│ Flutter App llama: supabase.auth.signUp()                       │
│ (con metadata: {role: 'cliente'|'restaurante'|'repartidor'})   │
└──────────────────────────┬──────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ Supabase Auth crea usuario en auth.users                        │
│ (con raw_user_meta_data: {role, name, phone, etc.})            │
└──────────────────────────┬──────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ TRIGGER: on_auth_user_created (AFTER INSERT)                    │
│ Ejecuta: master_handle_signup(NEW.id, NEW.raw_user_meta_data)  │
└──────────────────────────┬──────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ FUNCIÓN MAESTRA: master_handle_signup()                         │
│ 1. Extrae role de metadata (o default: 'cliente')               │
│ 2. INSERT INTO public.users (con rol correcto)                  │
│ 3. CASE role:                                                   │
│    - 'cliente' → INSERT client_profiles + account (client)      │
│    - 'restaurante' → INSERT restaurants + account (restaurant)  │
│    - 'repartidor' → INSERT delivery_agent_profiles              │
│                     + account (delivery_agent)                  │
│ 4. INSERT INTO user_preferences                                 │
│ 5. Log exhaustivo en debug_user_signup_log                     │
│ 6. Si falla CUALQUIER paso → ROLLBACK + log de error           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📋 PLAN DE IMPLEMENTACIÓN (3 FASES)

---

### **FASE 1: LIMPIEZA QUIRÚRGICA** 🧹

**Objetivo:** Eliminar funciones/triggers obsoletos sin romper nada en producción.

#### **1.1 Backup de funciones obsoletas**
Script: `cleanup_01_backup_obsolete.sql`

Crear tabla de backup:
```sql
CREATE TABLE IF NOT EXISTS public._backup_obsolete_functions (
  id bigserial PRIMARY KEY,
  function_name text NOT NULL,
  function_source text NOT NULL,
  backed_up_at timestamptz DEFAULT now()
);
```

Hacer backup de TODAS las funciones obsoletas antes de eliminar.

#### **1.2 Desactivar triggers obsoletos**
Script: `cleanup_02_disable_obsolete_triggers.sql`

Desactivar (NO eliminar) triggers conflictivos:
```sql
-- Desactivar triggers que NO necesitamos
ALTER TABLE public.delivery_agent_profiles DISABLE TRIGGER audit_delivery_agent_insert;
ALTER TABLE public.delivery_agent_profiles DISABLE TRIGGER delivery_agent_profiles_guard;
ALTER TABLE public.users DISABLE TRIGGER create_account_on_user_approval;
```

#### **1.3 Eliminar RPCs públicos innecesarios**
Script: `cleanup_03_drop_obsolete_rpcs.sql`

Eliminar RPCs que NO deben ser llamados desde Flutter:
```sql
DROP FUNCTION IF EXISTS public.register_client CASCADE;
DROP FUNCTION IF EXISTS public.register_delivery_agent CASCADE;
DROP FUNCTION IF EXISTS public.register_delivery_agent_atomic CASCADE;
DROP FUNCTION IF EXISTS public.register_restaurant CASCADE;
DROP FUNCTION IF EXISTS public.register_restaurant_v2 CASCADE;
DROP FUNCTION IF EXISTS public.create_user_profile_public CASCADE;
DROP FUNCTION IF EXISTS public.create_delivery_agent CASCADE;
DROP FUNCTION IF EXISTS public.create_restaurant_public CASCADE;
DROP FUNCTION IF EXISTS public.ensure_user_profile_public CASCADE;
DROP FUNCTION IF EXISTS public.ensure_user_profile_v2 CASCADE;
DROP FUNCTION IF EXISTS public.ensure_client_profile_and_account CASCADE;
DROP FUNCTION IF EXISTS public.ensure_delivery_agent_role_and_profile CASCADE;
DROP FUNCTION IF EXISTS public.ensure_my_delivery_profile CASCADE;
```

---

### **FASE 2: IMPLEMENTACIÓN DE ARQUITECTURA NUEVA** 🏗️

**Objetivo:** Crear una función maestra atómica y profesional.

#### **2.1 Crear función maestra de signup**
Script: `implementation_01_master_signup_function.sql`

```sql
CREATE OR REPLACE FUNCTION public.master_handle_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_email TEXT;
  v_role TEXT;
  v_name TEXT;
  v_phone TEXT;
  v_metadata JSONB;
BEGIN
  -- Extraer metadata
  v_email := NEW.email;
  v_metadata := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
  v_role := COALESCE(v_metadata->>'role', 'cliente');
  v_name := COALESCE(v_metadata->>'name', v_email);
  v_phone := v_metadata->>'phone';

  -- Normalizar rol
  v_role := CASE lower(v_role)
    WHEN 'client' THEN 'cliente'
    WHEN 'restaurant' THEN 'restaurante'
    WHEN 'delivery_agent' THEN 'repartidor'
    ELSE lower(v_role)
  END;

  -- Log START
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('master_handle_signup', 'START', v_role, NEW.id, v_email, v_metadata);

  -- PASO 1: Crear public.users
  INSERT INTO public.users (id, email, role, name, phone, created_at, updated_at, email_confirm)
  VALUES (NEW.id, v_email, v_role, v_name, v_phone, now(), now(), false)
  ON CONFLICT (id) DO UPDATE
  SET email = EXCLUDED.email, role = EXCLUDED.role, name = EXCLUDED.name, 
      phone = EXCLUDED.phone, updated_at = now();

  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
  VALUES ('master_handle_signup', 'USER_CREATED', v_role, NEW.id, v_email);

  -- PASO 2: Crear profile según rol
  CASE v_role
    WHEN 'cliente' THEN
      -- Cliente: crear client_profile + account (client)
      INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
      VALUES (NEW.id, 'active', now(), now())
      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();

      INSERT INTO public.accounts (id, user_id, account_type, balance, created_at, updated_at)
      VALUES (uuid_generate_v4(), NEW.id, 'client', 0.00, now(), now())
      ON CONFLICT (user_id, account_type) DO NOTHING;

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
      VALUES ('master_handle_signup', 'CLIENT_PROFILE_CREATED', v_role, NEW.id, v_email);

    WHEN 'restaurante' THEN
      -- Restaurante: crear restaurants (status=pending, NO crear account aún)
      INSERT INTO public.restaurants (id, user_id, name, status, created_at, updated_at, online)
      VALUES (uuid_generate_v4(), NEW.id, v_name || '''s Restaurant', 'pending', now(), now(), false)
      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
      VALUES ('master_handle_signup', 'RESTAURANT_CREATED', v_role, NEW.id, v_email);

    WHEN 'repartidor' THEN
      -- Repartidor: crear delivery_agent_profile (account_state=pending, NO crear account aún)
      INSERT INTO public.delivery_agent_profiles (user_id, status, account_state, created_at, updated_at)
      VALUES (NEW.id, 'pending', 'pending', now(), now())
      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();

      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
      VALUES ('master_handle_signup', 'DELIVERY_PROFILE_CREATED', v_role, NEW.id, v_email);

    ELSE
      RAISE EXCEPTION 'Invalid role: %', v_role;
  END CASE;

  -- PASO 3: Crear user_preferences
  INSERT INTO public.user_preferences (user_id, created_at, updated_at)
  VALUES (NEW.id, now(), now())
  ON CONFLICT (user_id) DO NOTHING;

  -- Log SUCCESS
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)
  VALUES ('master_handle_signup', 'SUCCESS', v_role, NEW.id, v_email);

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    -- Log ERROR
    INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
    VALUES ('master_handle_signup', 'ERROR', v_role, NEW.id, v_email,
            jsonb_build_object('error', SQLERRM, 'state', SQLSTATE));
    
    -- Re-lanzar el error para que Supabase Auth devuelva 500 y rollback
    RAISE;
END;
$function$;
```

#### **2.2 Reemplazar trigger existente**
Script: `implementation_02_replace_trigger.sql`

```sql
-- Eliminar trigger anterior
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Crear nuevo trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.master_handle_signup();

COMMENT ON TRIGGER on_auth_user_created ON auth.users IS 
  'Master signup trigger - crea public.users + profile según rol (cliente/restaurante/repartidor)';
```

#### **2.3 Grant permisos**
Script: `implementation_03_grant_permissions.sql`

```sql
-- Revocar permisos de funciones obsoletas
REVOKE ALL ON FUNCTION public.register_client(...) FROM anon, authenticated;
-- (repetir para todas las funciones obsoletas)

-- Asegurar que el trigger tiene permisos
GRANT EXECUTE ON FUNCTION public.master_handle_signup() TO postgres;
```

---

### **FASE 3: VALIDACIÓN Y TESTS** ✅

**Objetivo:** Probar exhaustivamente el nuevo flujo de signup.

#### **3.1 Tests de signup**
Script: `validation_01_test_signup.sql`

```sql
-- Test 1: Signup de cliente
DO $$
DECLARE
  v_test_email TEXT := 'test_client_' || extract(epoch from now()) || '@test.com';
  v_auth_id UUID;
BEGIN
  -- Simular INSERT en auth.users
  INSERT INTO auth.users (id, email, raw_user_meta_data, created_at, updated_at)
  VALUES (uuid_generate_v4(), v_test_email, '{"role":"cliente","name":"Test Cliente"}'::jsonb, now(), now())
  RETURNING id INTO v_auth_id;

  -- Verificar que se creó todo correctamente
  ASSERT EXISTS (SELECT 1 FROM public.users WHERE id = v_auth_id AND role = 'cliente');
  ASSERT EXISTS (SELECT 1 FROM public.client_profiles WHERE user_id = v_auth_id);
  ASSERT EXISTS (SELECT 1 FROM public.accounts WHERE user_id = v_auth_id AND account_type = 'client');
  ASSERT EXISTS (SELECT 1 FROM public.user_preferences WHERE user_id = v_auth_id);

  RAISE NOTICE '✅ Test Cliente: PASSED';
END $$;

-- Test 2: Signup de restaurante
-- (similar al anterior, verificando que se crea restaurants y NO account)

-- Test 3: Signup de repartidor
-- (similar, verificando que se crea delivery_agent_profiles y NO account)

-- Test 4: Rollback en caso de error
-- (forzar un error y verificar que NO se crea nada en public.users ni profiles)
```

#### **3.2 Cleanup de datos de prueba**
Script: `validation_02_cleanup_tests.sql`

```sql
-- Eliminar todos los usuarios de prueba creados en validation_01
DELETE FROM public.users WHERE email LIKE 'test_%@test.com';
DELETE FROM auth.users WHERE email LIKE 'test_%@test.com';
```

---

## 📁 SCRIPTS A CREAR

```
supabase_scripts/refactor_2025/
│
├── MASTER_PLAN_SIGNUP_REFACTOR.md (este archivo)
│
├── FASE 1: LIMPIEZA
│   ├── cleanup_01_backup_obsolete.sql
│   ├── cleanup_02_disable_obsolete_triggers.sql
│   └── cleanup_03_drop_obsolete_rpcs.sql
│
├── FASE 2: IMPLEMENTACIÓN
│   ├── implementation_01_master_signup_function.sql
│   ├── implementation_02_replace_trigger.sql
│   └── implementation_03_grant_permissions.sql
│
└── FASE 3: VALIDACIÓN
    ├── validation_01_test_signup.sql
    └── validation_02_cleanup_tests.sql
```

---

## 🚀 ORDEN DE EJECUCIÓN

### **PRODUCCIÓN:**

1. ✅ **AUDITORÍA (YA COMPLETADA)**
   - audit_01_list_all_signup_functions.sql
   - audit_02_list_all_triggers.sql
   - audit_03_list_all_rpcs.sql
   - audit_04_verify_schema.sql

2. 🧹 **LIMPIEZA**
   - cleanup_01_backup_obsolete.sql
   - cleanup_02_disable_obsolete_triggers.sql
   - cleanup_03_drop_obsolete_rpcs.sql

3. 🏗️ **IMPLEMENTACIÓN**
   - implementation_01_master_signup_function.sql
   - implementation_02_replace_trigger.sql
   - implementation_03_grant_permissions.sql

4. ✅ **VALIDACIÓN**
   - validation_01_test_signup.sql
   - validation_02_cleanup_tests.sql

---

## 🎯 BENEFICIOS DE ESTA ARQUITECTURA

1. **Atómica:** Si falla cualquier paso, se hace ROLLBACK completo
2. **Profesional:** Una sola función maestra, sin redundancia
3. **Extensible:** Fácil agregar nuevos roles en el CASE
4. **Debuggeable:** Logs exhaustivos en cada paso
5. **Segura:** SECURITY DEFINER con search_path fijo
6. **Limpia:** Elimina 13+ funciones obsoletas y triggers conflictivos
7. **Mantenible:** Código centralizado en una sola función
8. **Compatible:** Respeta el schema existente sin romper foreign keys

---

## ⚠️ CONSIDERACIONES IMPORTANTES

1. **NO TOCAR:** Ninguna tabla de balance, orders, settlements, o financial_system
2. **BACKUP:** Todas las funciones obsoletas se respaldan antes de eliminar
3. **ROLLBACK:** Si algo falla en producción, simplemente ejecutar:
   ```sql
   -- Restaurar trigger anterior
   DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
   CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
   FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
   ```

4. **LOGS:** Revisar `debug_user_signup_log` después de cada signup para verificar el flujo

---

## 📝 PRÓXIMOS PASOS INMEDIATOS

1. **Revisar y aprobar este plan**
2. **Crear los 8 scripts SQL** (cleanup + implementation + validation)
3. **Ejecutar en orden** en el SQL Editor de Supabase
4. **Probar signup desde Flutter** con los 3 roles
5. **Verificar logs** en `debug_user_signup_log`

---

## 💬 PREGUNTAS FRECUENTES

**Q: ¿Por qué no crear `accounts` para restaurante/repartidor en el signup?**
A: Porque el flujo actual requiere que el admin apruebe primero (`status='approved'`), y ENTONCES se crea el account. Respetamos esa lógica.

**Q: ¿Qué pasa si el usuario ya existe en `public.users`?**
A: Usamos `ON CONFLICT (id) DO UPDATE` para actualizar datos, no fallar.

**Q: ¿Cómo manejo metadata adicional (phone, address, etc.)?**
A: La función `master_handle_signup()` puede extraer cualquier campo de `raw_user_meta_data` y pasarlo a las tablas correspondientes.

**Q: ¿Qué pasa si falla un INSERT en `client_profiles`?**
A: La transacción completa hace ROLLBACK, incluyendo el `INSERT` en `public.users`. Nada queda inconsistente.

---

✅ **Este es un plan profesional, quirúrgico y completo. Espero tu aprobación para crear los scripts SQL.**
