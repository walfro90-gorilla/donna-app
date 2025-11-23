# 🔧 GUÍA PASO A PASO - FINALIZACIÓN DE REFACTORIZACIÓN

## ✅ Scripts Ya Ejecutados (1-7)

Has completado exitosamente los primeros 7 scripts:
1. ✅ `01_backup_current_state.sql`
2. ✅ `02_cleanup_obsolete_functions.sql`
3. ✅ `03_cleanup_triggers.sql`
4. ✅ `04_migrate_data.sql`
5. ✅ `05_alter_tables.sql`
6. ✅ `06_create_register_client.sql`
7. ✅ `07_create_register_restaurant.sql`

---

## ⚠️ PROBLEMA DETECTADO - Script 8 y 9

### Error en Script 8 (register_delivery_agent):
```
ERROR: 42725: function name "public.register_delivery_agent" is not unique
```

### Error en Script 9 (update_rls_policies):
```
ERROR: 42710: policy "users_update_own" for table "users" already exists
```

---

## 🔧 SOLUCIÓN - Scripts a Ejecutar

### **PASO 1: Limpiar funciones ambiguas**

Ejecuta estos 3 scripts fix (ubicados en `supabase_scripts/fixes/`):

```bash
1️⃣ fix_ambiguous_register_delivery_agent.sql
2️⃣ fix_ambiguous_register_restaurant.sql  
3️⃣ fix_ambiguous_register_client.sql
```

**Qué hacen:** Eliminan todas las sobrecargas (overloads) de las funciones de registro para evitar ambigüedad.

---

### **PASO 2: Crear la función de registro de repartidor**

Ejecuta el script:

```bash
4️⃣ 08_create_register_delivery_agent.sql
```

**Qué hace:** Crea la función `register_delivery_agent` limpia y atómica.

---

### **PASO 3: Limpiar políticas RLS antiguas**

Ejecuta el script:

```bash
5️⃣ 09_cleanup_all_policies.sql (NUEVO - creado para ti)
```

**Qué hace:** Elimina TODAS las políticas RLS existentes de las tablas `users`, `client_profiles`, `restaurants`, `delivery_agent_profiles`, `accounts`, y `user_preferences`.

**Ubicación:** `/supabase_scripts/refactor_2025/09_cleanup_all_policies.sql`

---

### **PASO 4: Crear políticas RLS nuevas**

Ejecuta el script:

```bash
6️⃣ 09_update_rls_policies_fixed.sql (NUEVO - versión idempotente)
```

**Qué hace:** Crea todas las políticas RLS nuevas de forma idempotente (puede ejecutarse múltiples veces sin fallar).

**Ubicación:** `/supabase_scripts/refactor_2025/09_update_rls_policies_fixed.sql`

---

### **PASO 5: Probar los 3 procesos de registro**

Ejecuta el script:

```bash
7️⃣ 10_test_registrations.sql
```

**Qué hace:** 
- Crea usuarios de prueba (cliente, restaurante, repartidor)
- Verifica que todos los datos relacionados se crearon correctamente
- Prueba validaciones (emails duplicados, passwords cortos, etc.)
- Muestra un resumen de integridad de datos

**⚠️ Nota:** Este script es para testing. Puedes ejecutarlo en ambiente de desarrollo/staging.

---

### **PASO 6: Crear índices de optimización**

Ejecuta el script:

```bash
8️⃣ 11_create_indexes.sql
```

**Qué hace:**
- Crea ~40 índices optimizados en todas las tablas principales
- Mejora la performance de consultas críticas
- Ejecuta ANALYZE en las tablas
- Incluye índices especiales para búsquedas geográficas y filtros complejos

---

## 📋 RESUMEN DE EJECUCIÓN

### Orden correcto de scripts faltantes:

```
✅ Scripts ya ejecutados (1-7)

🔧 Scripts de corrección:
   1. fixes/fix_ambiguous_register_delivery_agent.sql
   2. fixes/fix_ambiguous_register_restaurant.sql
   3. fixes/fix_ambiguous_register_client.sql

📝 Scripts de refactorización:
   4. 08_create_register_delivery_agent.sql
   5. 09_cleanup_all_policies.sql (NUEVO)
   6. 09_update_rls_policies_fixed.sql (NUEVO)
   7. 10_test_registrations.sql
   8. 11_create_indexes.sql
```

---

## 🎯 ARCHIVOS NUEVOS CREADOS

He creado 2 archivos nuevos para resolver los errores:

1. **`09_cleanup_all_policies.sql`**
   - Ubicación: `supabase_scripts/refactor_2025/`
   - Elimina todas las políticas RLS existentes de forma segura
   
2. **`09_update_rls_policies_fixed.sql`**
   - Ubicación: `supabase_scripts/refactor_2025/`
   - Versión idempotente del script 09 original
   - Usa `DROP POLICY IF EXISTS ... CASCADE` antes de crear cada política

---

## ⚡ COMANDOS RÁPIDOS

Copia y pega estos scripts en Supabase SQL Editor en este orden:

### 1. Limpieza de funciones ambiguas
```sql
-- Archivo: fixes/fix_ambiguous_register_delivery_agent.sql
-- Copiar y pegar contenido completo
```

```sql
-- Archivo: fixes/fix_ambiguous_register_restaurant.sql
-- Copiar y pegar contenido completo
```

```sql
-- Archivo: fixes/fix_ambiguous_register_client.sql
-- Copiar y pegar contenido completo
```

### 2. Crear función de delivery agent
```sql
-- Archivo: 08_create_register_delivery_agent.sql
-- Copiar y pegar contenido completo
```

### 3. Limpiar políticas RLS
```sql
-- Archivo: 09_cleanup_all_policies.sql
-- Copiar y pegar contenido completo
```

### 4. Crear políticas RLS nuevas
```sql
-- Archivo: 09_update_rls_policies_fixed.sql
-- Copiar y pegar contenido completo
```

### 5. Testing de registros
```sql
-- Archivo: 10_test_registrations.sql
-- Copiar y pegar contenido completo
```

### 6. Crear índices
```sql
-- Archivo: 11_create_indexes.sql
-- Copiar y pegar contenido completo
```

---

## ✅ VERIFICACIÓN FINAL

Después de ejecutar todos los scripts, verifica:

1. **Funciones RPC creadas:**
```sql
SELECT 
  proname as function_name,
  pg_get_function_arguments(oid) as arguments
FROM pg_proc
WHERE proname IN (
  'register_client',
  'register_restaurant', 
  'register_delivery_agent'
)
AND pronamespace = 'public'::regnamespace;
```

Deberías ver exactamente 3 funciones, cada una con su lista de argumentos correcta.

2. **Políticas RLS creadas:**
```sql
SELECT 
  tablename,
  policyname,
  cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'users',
    'client_profiles',
    'restaurants',
    'delivery_agent_profiles',
    'accounts',
    'user_preferences'
  )
ORDER BY tablename, policyname;
```

Deberías ver ~15 políticas en total.

3. **Índices creados:**
```sql
SELECT 
  tablename,
  COUNT(*) as num_indexes
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
    'users',
    'client_profiles',
    'restaurants',
    'delivery_agent_profiles',
    'accounts'
  )
GROUP BY tablename
ORDER BY tablename;
```

Deberías ver múltiples índices por tabla.

---

## 🚨 NOTAS IMPORTANTES

1. **Idempotencia:** Los scripts nuevos (09_cleanup y 09_fixed) son completamente idempotentes. Puedes ejecutarlos múltiples veces sin problemas.

2. **Rollback:** Si algo falla, puedes restaurar desde el backup que creaste en el script 01.

3. **Testing:** El script 10 crea usuarios de prueba. Puedes eliminarlos después con:
```sql
DELETE FROM auth.users WHERE email LIKE '%refactor@example.com';
```

4. **Performance:** Los índices del script 11 mejorarán significativamente la performance de consultas, especialmente en la tabla `orders`.

---

## 📞 ¿NECESITAS AYUDA?

Si algún script falla:
1. Copia el error completo
2. Indica qué script estabas ejecutando
3. Revisa el console log de Supabase para más detalles

---

## 🎉 ¡ÉXITO!

Una vez completados todos los scripts, tu base de datos estará completamente refactorizada con:
- ✅ Procesos atómicos de registro
- ✅ Políticas RLS optimizadas
- ✅ Índices de alto rendimiento
- ✅ Validaciones robustas
- ✅ Estructura limpia y profesional

---

*Última actualización: Enero 2025*
*Refactorización de BD - Proyecto Delivery App*
