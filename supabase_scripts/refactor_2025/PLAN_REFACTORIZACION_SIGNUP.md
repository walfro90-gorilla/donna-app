# 🎯 PLAN PROFESIONAL: REFACTORIZACIÓN SIGNUP & PROFILES

## 📊 ESQUEMA BASE (según DATABASE_SCHEMA.sql)

```
auth.users (tabla de Supabase Auth)
    ↓ (id)
public.users (id references auth.users.id)
    ↓ (id = user_id)
    ├── public.client_profiles (user_id references users.id)
    ├── public.delivery_agent_profiles (user_id references users.id)
    └── public.restaurants (user_id references users.id)
```

---

## 🎯 OBJETIVO

**Crear un flujo atómico y quirúrgico de signup** que:
1. ✅ Supabase Auth crea el usuario en `auth.users`
2. ✅ Un trigger automático crea el registro en `public.users`
3. ✅ Según el rol, crea el perfil correspondiente (client_profiles, delivery_agent_profiles, o restaurants)
4. ✅ Todo en una transacción atómica (rollback si falla cualquier paso)
5. ✅ Elimina funciones/triggers obsoletos que causan conflictos

---

## 📋 PLAN DE 3 FASES

### **FASE 1: AUDITORÍA COMPLETA** ✅

**Objetivo:** Inventariar TODAS las funciones, triggers y RPCs relacionados con signup/profiles para identificar qué está obsoleto, redundante o en conflicto.

#### Scripts de auditoría (ejecutar en orden):

1. **`audit_01_list_all_signup_functions.sql`**
   - Lista TODAS las funciones en `public` y `auth` relacionadas con signup/profiles
   - Muestra el código fuente completo de cada función
   - Identifica funciones que manipulan `users`, `client_profiles`, `delivery_agent_profiles`, `restaurants`

2. **`audit_02_list_all_triggers.sql`**
   - Lista TODOS los triggers en `auth.users` y tablas de profiles
   - Muestra el código fuente de las funciones que ejecutan los triggers
   - Identifica triggers activos, deshabilitados, y en conflicto

3. **`audit_03_list_all_rpcs.sql`**
   - Lista TODOS los RPCs públicos accesibles desde Flutter
   - Muestra permisos (anon, authenticated)
   - Identifica RPCs obsoletos o redundantes

4. **`audit_04_verify_schema.sql`**
   - Verifica la estructura real de las tablas críticas
   - Confirma foreign keys: `users.id → auth.users.id`, `profiles.user_id → users.id`
   - Identifica discrepancias con `DATABASE_SCHEMA.sql`

#### Qué necesito:
- Ejecuta los 4 scripts en el SQL Editor de Supabase
- Copia el resultado completo de cada uno (especialmente columna `function_source`)
- Envíamelos para analizar

---

### **FASE 2: DISEÑO DE ARQUITECTURA LIMPIA** 🏗️

**Objetivo:** Con los resultados de la auditoría, diseñaré una arquitectura limpia y profesional.

#### Lo que haré:

1. **Mapear el flujo actual**
   - Qué se ejecuta cuando haces signup
   - En qué orden
   - Qué funciones/triggers están en conflicto

2. **Identificar lo obsoleto**
   - Funciones redundantes (ej: múltiples `handle_new_user`)
   - Triggers duplicados
   - RPCs no utilizados o peligrosos

3. **Diseñar la arquitectura nueva**
   ```sql
   auth.users (signup por Supabase Auth)
       ↓
   TRIGGER on_auth_user_created (AFTER INSERT)
       ↓
   FUNCIÓN master_create_user_and_profile(
       user_id,
       email,
       role,
       metadata_jsonb
   )
       ↓
   1. INSERT INTO public.users
   2. CASE role:
      'cliente' → INSERT INTO client_profiles
      'repartidor' → INSERT INTO delivery_agent_profiles
      'restaurante' → INSERT INTO restaurants
   3. COMMIT (o ROLLBACK si falla)
   ```

4. **Documentar el plan de limpieza**
   - Qué funciones eliminar (con backup en comentarios)
   - Qué triggers eliminar
   - Qué RPCs eliminar

#### Entregable:
- Documento detallado con el diseño de la arquitectura limpia
- Script SQL de la nueva función maestra
- Plan de eliminación de código obsoleto

---

### **FASE 3: IMPLEMENTACIÓN QUIRÚRGICA** 🔧

**Objetivo:** Implementar la nueva arquitectura sin romper nada existente.

#### Scripts a crear:

1. **`cleanup_01_backup_old_functions.sql`**
   - Hace backup de TODAS las funciones/triggers obsoletos (como comentarios)
   - Documenta qué se va a eliminar y por qué

2. **`cleanup_02_drop_obsolete.sql`**
   - Elimina triggers obsoletos
   - Elimina funciones redundantes
   - Elimina RPCs peligrosos

3. **`implementation_01_create_master_function.sql`**
   - Crea la nueva función maestra atómica
   - Maneja creación de `public.users` + profile según rol
   - Incluye logging para debugging

4. **`implementation_02_create_trigger.sql`**
   - Crea el trigger limpio en `auth.users`
   - Llama a la función maestra

5. **`implementation_03_grant_permissions.sql`**
   - Otorga permisos necesarios
   - Configura RLS policies

6. **`validation_01_test_signup.sql`**
   - Tests de signup para cada rol (cliente, repartidor, restaurante)
   - Verifica rollback si falla

#### Entregable:
- Scripts SQL listos para ejecutar en orden
- Documentación de cada paso
- Plan de rollback si algo sale mal

---

## 🚀 PRÓXIMO PASO INMEDIATO

**Por favor ejecuta los 4 scripts de auditoría (FASE 1) y envíame los resultados completos.**

Con esos resultados haré el análisis quirúrgico y diseñaré la arquitectura limpia para las fases 2 y 3.

---

## 📝 NOTAS IMPORTANTES

- ❌ **NO tocar nada de balance 0 ni entregas** (solo signup y profiles)
- ✅ **Backup de todo antes de eliminar** (en comentarios SQL)
- ✅ **Transacciones atómicas** (rollback si falla)
- ✅ **Logging exhaustivo** para debugging
- ✅ **Tests de validación** antes de cerrar

---

## 📁 ESTRUCTURA DE ARCHIVOS

```
supabase_scripts/refactor_2025/
├── PLAN_REFACTORIZACION_SIGNUP.md (este archivo)
│
├── FASE 1: AUDITORÍA
│   ├── audit_01_list_all_signup_functions.sql ✅ CORREGIDO
│   ├── audit_02_list_all_triggers.sql ✅ CORREGIDO (v2 - sin pg_stat_user_tables)
│   ├── audit_03_list_all_rpcs.sql ✅ CORREGIDO
│   └── audit_04_verify_schema.sql ✅ NUEVO
│
├── FASE 2: DISEÑO (pendiente resultados auditoría)
│   └── DISEÑO_ARQUITECTURA_LIMPIA.md
│
└── FASE 3: IMPLEMENTACIÓN (pendiente diseño)
    ├── cleanup_01_backup_old_functions.sql
    ├── cleanup_02_drop_obsolete.sql
    ├── implementation_01_create_master_function.sql
    ├── implementation_02_create_trigger.sql
    ├── implementation_03_grant_permissions.sql
    └── validation_01_test_signup.sql
```
