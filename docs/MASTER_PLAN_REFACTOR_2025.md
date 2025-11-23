# 🚀 PLAN MAESTRO DE REFACTORIZACIÓN - DOA REPARTOS 2025

## 📋 RESUMEN EJECUTIVO

Este documento describe el plan completo para simplificar y profesionalizar el sistema de registro y gestión de usuarios en Doa Repartos. El objetivo es tener **3 procesos atómicos de registro** que se ejecuten de manera confiable y mantenible.

---

## 🎯 OBJETIVOS

### Principales
1. **Simplificar** las tablas eliminando campos redundantes
2. **Atomizar** los 3 procesos de registro (Cliente, Restaurante, Repartidor)
3. **Consolidar** la lógica en RPCs modernos y seguros
4. **Eliminar** triggers conflictivos y código obsoleto
5. **Normalizar** la estructura de datos

### Métricas de Éxito
- ✅ 1 RPC por tipo de registro (3 total)
- ✅ 0 triggers automáticos en auth.users
- ✅ Todas las tablas con campos mínimos necesarios
- ✅ Tests de registro funcionando al 100%

---

## 📊 ESTADO ACTUAL DEL SISTEMA

### **Tabla: `public.users`**
**Campos actuales:** 15
**Campos necesarios:** 9
**Campos a eliminar:** 6

| Campo | Estado | Acción |
|-------|--------|--------|
| `id` | ✅ Mantener | UUID principal |
| `email` | ✅ Mantener | Email único |
| `name` | ✅ Mantener | Nombre completo |
| `phone` | ✅ Mantener | Teléfono |
| `role` | ✅ Mantener | Rol del usuario |
| `email_confirm` | ✅ Mantener | Estado verificación |
| `created_at` | ✅ Mantener | Timestamp creación |
| `updated_at` | ✅ Mantener | Timestamp actualización |
| `avatar_url` | ⚠️ Mover | → `client_profiles.profile_image_url` |
| `status` | ❌ ELIMINAR | Redundante con roles específicos |
| `average_rating` | ❌ ELIMINAR | Se calcula desde `reviews` |
| `total_reviews` | ❌ ELIMINAR | Se calcula desde `reviews` |
| `current_location` | ❌ ELIMINAR | Ya existe en `courier_locations_latest` |
| `current_heading` | ❌ ELIMINAR | Ya existe en `courier_locations_latest` |

### **Tabla: `client_profiles`**
**Estado:** ✅ Bien estructurada
**Campos a agregar:** 1

| Campo | Acción |
|-------|--------|
| `profile_image_url` | ➕ AGREGAR (mover desde users) |

### **Tabla: `restaurants`**
**Estado:** ✅ Estructura correcta
**Campos:** 28 (todos necesarios)

### **Tabla: `delivery_agent_profiles`**
**Estado:** ✅ Estructura correcta
**Campos:** 16 (todos necesarios)
**Nota:** Incluye `status` (online/offline) y `account_state` (pending/approved)

### **Tabla: `accounts`**
**Estado:** ✅ Estructura correcta
**Tipos permitidos:** `restaurant`, `delivery_agent`, `platform`, `platform_revenue`, `platform_payables`

---

## 🗑️ LIMPIEZA NECESARIA

### 1. **Triggers a ELIMINAR**
```sql
-- Estos triggers causan conflictos y deben eliminarse
DROP TRIGGER IF EXISTS ensure_user_profile ON auth.users;
DROP FUNCTION IF EXISTS ensure_user_profile_public();
```

### 2. **RPCs Obsoletos a ELIMINAR** (Total: ~50)
- Todos los RPCs legacy de registro
- RPCs con nombres duplicados o versiones antiguas
- RPCs de testing y debug que quedaron en producción

**Lista completa en:** `01_cleanup_obsolete_functions.sql`

### 3. **Políticas RLS a REVISAR**
- Simplificar políticas de `users` (ya no usa `status`)
- Actualizar políticas que dependan de campos eliminados

---

## 🏗️ ARQUITECTURA NUEVA

### **Flujo de Registro Universal**

```
┌─────────────────────────────────────────────────────┐
│  1. Frontend llama RPC específico                    │
│     - register_client(email, password, name, phone) │
│     - register_restaurant(...)                      │
│     - register_delivery_agent(...)                  │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  2. RPC crea usuario en auth.users                  │
│     auth.sign_up_v2(email, password, metadata)      │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  3. RPC inserta en public.users                     │
│     INSERT INTO users (id, email, name, phone,      │
│                        role, email_confirm)         │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  4. RPC crea perfil específico                      │
│     - client_profiles                               │
│     - restaurants                                   │
│     - delivery_agent_profiles                       │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  5. RPC crea cuenta (si aplica)                     │
│     - accounts (para restaurant/delivery_agent)     │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  6. RPC crea preferencias                           │
│     - user_preferences                              │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  7. RPC retorna usuario completo                    │
│     RETURN JSON con todos los datos                 │
└─────────────────────────────────────────────────────┘
```

### **Transaccionalidad**
- ✅ Todo en una sola transacción SQL
- ✅ Si falla cualquier paso, rollback automático
- ✅ Validaciones antes de crear en auth.users
- ✅ Logging de errores en tabla debug

---

## 📝 ESTRUCTURA FINAL DE TABLAS

### **`public.users` (Simplificada)**
```sql
CREATE TABLE public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id),
  email TEXT NOT NULL UNIQUE,
  name TEXT,
  phone TEXT,
  role TEXT NOT NULL DEFAULT 'cliente' 
       CHECK (role IN ('cliente', 'restaurante', 'repartidor', 'admin')),
  email_confirm BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### **`client_profiles` (Extendida)**
```sql
CREATE TABLE client_profiles (
  user_id UUID PRIMARY KEY REFERENCES users(id),
  profile_image_url TEXT,
  address TEXT,
  lat DOUBLE PRECISION,
  lon DOUBLE PRECISION,
  address_structured JSONB,
  average_rating NUMERIC DEFAULT 0.00,
  total_reviews INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### **`restaurants` (Sin cambios)**
```sql
-- Ya está bien estructurada
-- Contiene todos los campos necesarios para restaurantes
```

### **`delivery_agent_profiles` (Sin cambios)**
```sql
-- Ya está bien estructurada
-- Tiene status (online/offline) y account_state (pending/approved)
```

---

## 🔧 IMPLEMENTACIÓN POR FASES

### **FASE 1: Preparación y Backup** ⏱️ 5 min
```bash
# Ejecutar en SQL Editor de Supabase
01_backup_current_state.sql
```
- ✅ Crea backup de todas las tablas críticas
- ✅ Exporta RPCs actuales
- ✅ Documenta constraints y foreign keys

### **FASE 2: Limpieza** ⏱️ 10 min
```bash
02_cleanup_obsolete_functions.sql
03_cleanup_triggers.sql
```
- ✅ Elimina 50+ RPCs obsoletos
- ✅ Elimina triggers conflictivos
- ✅ Limpia vistas no usadas

### **FASE 3: Migración de Datos** ⏱️ 15 min
```bash
04_migrate_data.sql
```
- ✅ Mueve `users.avatar_url` → `client_profiles.profile_image_url`
- ✅ Crea `client_profiles` para usuarios sin perfil
- ✅ Valida integridad de datos

### **FASE 4: Modificación de Tablas** ⏱️ 10 min
```bash
05_alter_tables.sql
```
- ✅ Elimina columnas obsoletas de `users`
- ✅ Agrega `profile_image_url` a `client_profiles`
- ✅ Actualiza constraints

### **FASE 5: Nuevos RPCs** ⏱️ 20 min
```bash
06_create_register_client.sql
07_create_register_restaurant.sql
08_create_register_delivery_agent.sql
```
- ✅ Crea los 3 RPCs principales
- ✅ Con manejo de errores robusto
- ✅ Con validaciones completas
- ✅ Con logging

### **FASE 6: Políticas RLS** ⏱️ 10 min
```bash
09_update_rls_policies.sql
```
- ✅ Actualiza políticas de `users`
- ✅ Elimina referencias a campos borrados
- ✅ Simplifica permisos

### **FASE 7: Testing** ⏱️ 15 min
```bash
10_test_registrations.sql
```
- ✅ Test registro cliente
- ✅ Test registro restaurante
- ✅ Test registro repartidor
- ✅ Validación de rollbacks

### **FASE 8: Índices y Optimización** ⏱️ 5 min
```bash
11_create_indexes.sql
```
- ✅ Índices optimizados
- ✅ Análisis de queries comunes

---

## ⚠️ CONSIDERACIONES IMPORTANTES

### **Downtime**
- ⚠️ Se recomienda mantenimiento programado de **30-60 minutos**
- ⚠️ Las fases 2-5 requieren que no haya registros activos
- ✅ Los usuarios ya logueados no se verán afectados

### **Rollback**
- ✅ Backup completo en FASE 1
- ✅ Cada SQL tiene su reverso documentado
- ✅ Posible rollback hasta FASE 4

### **Testing**
- ✅ FASE 7 incluye tests completos
- ✅ Validar en ambiente staging primero
- ✅ Monitorear logs después de deployment

---

## 📞 CONTACTO Y SOPORTE

**Documentación:** `/docs`
**SQL Scripts:** `/supabase_scripts/refactor_2025/`
**Logs:** `public._debug_events`, `public.debug_logs`

---

## ✅ CHECKLIST DE EJECUCIÓN

- [ ] Fase 1: Backup completado
- [ ] Fase 2: Limpieza de RPCs y triggers
- [ ] Fase 3: Migración de datos validada
- [ ] Fase 4: Tablas alteradas correctamente
- [ ] Fase 5: Nuevos RPCs creados y probados
- [ ] Fase 6: Políticas RLS actualizadas
- [ ] Fase 7: Tests pasando al 100%
- [ ] Fase 8: Índices creados
- [ ] App Flutter actualizada para usar nuevos RPCs
- [ ] Monitoreo post-deployment activo

---

**Fecha de creación:** 2025-01-XX
**Versión:** 1.0
**Estado:** 🟡 Pendiente de ejecución
