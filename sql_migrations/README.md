# Migraciones SQL - Doa Repartos

Este directorio contiene los archivos SQL necesarios para configurar y limpiar la base de datos del sistema de delivery.

## 📋 Archivos Disponibles

### 1️⃣ `01_schema_tables.sql`
**Propósito:** Crear todas las tablas del schema desde cero
- ✅ Crea todas las tablas necesarias (users, restaurants, orders, products, etc.)
- ✅ Crea índices para optimización
- ✅ Configura triggers para `updated_at` automático
- ✅ Safe to run: usa `IF NOT EXISTS` en todas las creaciones

**Cuándo usar:** Setup inicial de la base de datos o recreación completa

---

### 2️⃣ `02_rls_policies.sql`
**Propósito:** Configurar Row Level Security (RLS)
- ✅ Habilita RLS en todas las tablas
- ✅ Crea policies para cada tabla según roles
- ✅ Controla acceso de clientes, restaurantes, repartidores y admins
- ✅ Safe to run: no falla si policies ya existen

**Cuándo usar:** Después de crear las tablas o para actualizar permisos

---

### 3️⃣ `03_functions_rpcs.sql`
**Propósito:** Crear funciones RPC (Remote Procedure Calls)
- ✅ Funciones de registro (restaurantes, repartidores)
- ✅ Funciones de órdenes (crear, aceptar, actualizar)
- ✅ Funciones de ubicación (tracking de repartidores)
- ✅ Funciones de cuentas financieras
- ✅ Safe to run: usa `CREATE OR REPLACE`

**Cuándo usar:** Después de crear las tablas o para actualizar funciones

---

### 4️⃣ `04_drop_problematic_triggers.sql` ⚠️
**Propósito:** ELIMINAR triggers que causan errores
- 🗑️ Elimina triggers que acceden a `OLD.status` donde no existe
- 🗑️ Limpia triggers en `client_profiles` y `users`
- 🗑️ Mantiene solo triggers esenciales (updated_at)
- ✅ Incluye diagnóstico antes y después

**Cuándo usar:** 
- ❌ Cuando ves error: `record "old" has no field "status" (42703)`
- ❌ Cuando `ensure_user_profile_public()` falla
- ❌ Cuando el registro de restaurantes no funciona

**⚠️ IMPORTANTE:** Este es el archivo que necesitas para resolver el error actual

---

### 5️⃣ `05_cleanup_unused_functions.sql` 🧹
**Propósito:** Eliminar funciones legacy/duplicadas
- 🗑️ Elimina `create_user_profile_public` (usar `ensure_user_profile_v2`)
- 🗑️ Elimina `create_restaurant_public` (usar `register_restaurant_v2`)
- 🗑️ Elimina `create_account_public` (usar `ensure_account_v2`)
- 🗑️ Elimina funciones de status sync problemáticas
- ✅ Incluye listado de funciones antes y después

**Cuándo usar:**
- 🧹 Después de migrar a las nuevas funciones v2
- 🧹 Para limpiar funciones que causan confusión
- 🧹 Para reducir el número de RPCs disponibles

---

## 🚀 Orden de Ejecución Recomendado

### Setup Inicial (Base de datos nueva)
```sql
-- 1. Crear schema completo
\i 01_schema_tables.sql

-- 2. Configurar seguridad
\i 02_rls_policies.sql

-- 3. Crear funciones
\i 03_functions_rpcs.sql
```

### Resolver Error Actual (record "old" has no field "status")
```sql
-- SOLO ejecutar estos dos archivos en orden:

-- 1. Eliminar triggers problemáticos
\i 04_drop_problematic_triggers.sql

-- 2. Limpiar funciones legacy
\i 05_cleanup_unused_functions.sql
```

---

## 🎯 Solución al Error Actual

### Error Reportado:
```
❌ ensureUserProfile PostgREST error: record "old" has no field "status" (42703)
❌ [RPC] create_restaurant_public error: Could not find the function
```

### Causa:
- Hay triggers que intentan acceder a `OLD.status` en tablas que no tienen ese campo
- La función `create_restaurant_public` no existe (es legacy)

### Solución:
```sql
-- Ejecutar en orden:
\i 04_drop_problematic_triggers.sql
\i 05_cleanup_unused_functions.sql
```

Esto va a:
1. ✅ Eliminar todos los triggers problemáticos
2. ✅ Eliminar funciones legacy que ya no se usan
3. ✅ Dejar solo las funciones v2 que funcionan correctamente
4. ✅ Mostrar diagnóstico completo en la consola

---

## 📝 Notas Importantes

### Funciones Principales (Usar Estas)
- ✅ `ensure_user_profile_v2()` - Crear/actualizar perfil usuario
- ✅ `register_restaurant_v2()` - Registro completo restaurante
- ✅ `register_delivery_agent_atomic()` - Registro completo repartidor
- ✅ `create_order_safe()` - Crear orden
- ✅ `accept_order()` - Repartidor acepta orden
- ✅ `update_user_location()` - Actualizar ubicación repartidor

### Funciones Legacy (NO Usar)
- ❌ `create_user_profile_public()` - ELIMINADA
- ❌ `create_restaurant_public()` - ELIMINADA
- ❌ `create_account_public()` - ELIMINADA

### Safe to Run Multiple Times
Todos los archivos son idempotentes y seguros de ejecutar múltiples veces:
- `IF NOT EXISTS` en creación de tablas
- `CREATE OR REPLACE` en funciones
- `DROP IF EXISTS` en limpiezas
- Diagnóstico incluido en cada paso

---

## 🔍 Verificación Post-Ejecución

Después de ejecutar los archivos de limpieza, verifica:

```sql
-- 1. Ver triggers restantes en client_profiles (debería ser 0 o solo updated_at)
SELECT tgname FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname = 'client_profiles' AND NOT t.tgisinternal;

-- 2. Ver triggers restantes en users (debería ser solo updated_at)
SELECT tgname FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname = 'users' AND NOT t.tgisinternal;

-- 3. Ver funciones RPC disponibles
SELECT proname, pg_get_function_identity_arguments(oid) 
FROM pg_proc 
WHERE pronamespace = 'public'::regnamespace 
  AND proname NOT LIKE 'pg_%'
ORDER BY proname;
```

---

## 📞 Soporte

Si después de ejecutar estos scripts sigues teniendo problemas:
1. Revisa los mensajes de NOTICE que genera cada script
2. Verifica que todas las funciones v2 estén creadas
3. Confirma que los triggers problemáticos fueron eliminados
4. Prueba el registro de restaurante nuevamente en la app
