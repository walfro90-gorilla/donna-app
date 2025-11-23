# 🚨 INSTRUCCIONES DE CORRECCIÓN - FUNCIONES DE REGISTRO

## 📊 DIAGNÓSTICO DEL PROBLEMA

El error que estás viendo:
```
ERROR: 42883: function public.register_client(...) does not exist
```

**Significa:** Las funciones de registro (`register_client`, `register_restaurant`, `register_delivery_agent`) **NO EXISTEN** en tu base de datos.

**Causa probable:** Los scripts 06, 07 y 08 no se ejecutaron correctamente, o fueron eliminados por algún otro proceso.

---

## ✅ SOLUCIÓN - ORDEN DE EJECUCIÓN

Sigue estos pasos **EN ORDEN EXACTO**:

### **PASO 1️⃣: Diagnóstico y Limpieza**

**Archivo:** `supabase_scripts/fixes/00_EXECUTE_THIS_FIRST_verify_and_recreate_functions.sql`

**Qué hace:**
- ✅ Verifica qué funciones de registro existen actualmente
- ✅ Elimina TODAS las versiones anteriores (si existen)
- ✅ Confirma que la limpieza fue exitosa

**Resultado esperado:** 
```
funciones_restantes = 0
```

---

### **PASO 2️⃣: Crear función register_client**

**Archivo:** `supabase_scripts/refactor_2025/06_create_register_client.sql`

**Qué hace:**
- ✅ Crea la función `public.register_client` con 8 parámetros
- ✅ Proceso atómico: auth.users → public.users → client_profiles → user_preferences
- ✅ Retorna JSONB con success/error

**Resultado esperado:** 
```
CREATE FUNCTION
```

---

### **PASO 3️⃣: Crear función register_restaurant**

**Archivo:** `supabase_scripts/refactor_2025/07_create_register_restaurant.sql`

**Qué hace:**
- ✅ Crea la función `public.register_restaurant` con 11 parámetros
- ✅ Proceso atómico: auth.users → public.users → restaurants → accounts → user_preferences → admin_notifications
- ✅ Retorna JSONB con success/error

**Resultado esperado:** 
```
CREATE FUNCTION
```

---

### **PASO 4️⃣: Crear función register_delivery_agent**

**Archivo:** `supabase_scripts/refactor_2025/08_create_register_delivery_agent.sql`

**Qué hace:**
- ✅ Crea la función `public.register_delivery_agent` con 7 parámetros
- ✅ Proceso atómico: auth.users → public.users → delivery_agent_profiles → accounts → user_preferences → admin_notifications
- ✅ Retorna JSONB con success/error

**Resultado esperado:** 
```
CREATE FUNCTION
```

---

### **PASO 5️⃣: Ejecutar tests de registro**

**Archivo:** `supabase_scripts/refactor_2025/10_test_registrations_fixed_v3.sql`

**Qué hace:**
- ✅ Prueba las 3 funciones de registro con datos aleatorios
- ✅ Muestra resultados en formato tabla
- ✅ Genera resumen de registros creados

**Resultado esperado:** 
```
test_name          | success | user_id              | message
-------------------|---------|---------------------|---------------------------
TEST_CLIENT        | true    | [uuid]              | Cliente registrado...
TEST_RESTAURANT    | true    | [uuid]              | Restaurante registrado...
TEST_DELIVERY_AGENT| true    | [uuid]              | Repartidor registrado...
```

---

### **PASO 6️⃣: Crear índices de rendimiento**

**Archivo:** `supabase_scripts/refactor_2025/11_create_indexes.sql`

**Qué hace:**
- ✅ Crea índices en columnas de búsqueda frecuente
- ✅ Mejora el rendimiento de queries
- ✅ Optimiza foreign keys

**Resultado esperado:** 
```
CREATE INDEX (múltiples veces)
```

---

## 🎯 RESUMEN DE ARCHIVOS A EJECUTAR

```
1. supabase_scripts/fixes/00_EXECUTE_THIS_FIRST_verify_and_recreate_functions.sql
2. supabase_scripts/refactor_2025/06_create_register_client.sql
3. supabase_scripts/refactor_2025/07_create_register_restaurant.sql
4. supabase_scripts/refactor_2025/08_create_register_delivery_agent.sql
5. supabase_scripts/refactor_2025/10_test_registrations_fixed_v3.sql
6. supabase_scripts/refactor_2025/11_create_indexes.sql
```

---

## 🚨 ERRORES COMUNES Y SOLUCIONES

### **Error: "function name is not unique"**
**Solución:** Vuelve a ejecutar el PASO 1 para limpiar todas las versiones anteriores

### **Error: "policy already exists"**
**Solución:** Ya fue resuelto con el script `fix_duplicate_policies.sql`

### **Error: "function does not exist"**
**Solución:** Estás en este caso ahora. Ejecuta PASOS 1-4 en orden

### **Error: "relation does not exist"**
**Solución:** Verifica que los scripts 01-05 se ejecutaron correctamente (tablas, tipos, etc.)

---

## ✅ CÓMO VERIFICAR QUE TODO FUNCIONÓ

Después de ejecutar todos los scripts, ejecuta esto en Supabase SQL Editor:

```sql
-- Verificar que las 3 funciones existen
SELECT 
  p.proname as function_name,
  pg_catalog.pg_get_function_arguments(p.oid) as arguments
FROM pg_catalog.pg_proc p
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('register_client', 'register_restaurant', 'register_delivery_agent')
ORDER BY p.proname;
```

**Resultado esperado:** 3 filas (una por cada función)

---

## 📞 SIGUIENTES PASOS DESPUÉS DE COMPLETAR

Una vez que todos los scripts se ejecuten exitosamente:

1. ✅ **Actualizar Flutter app** - Modificar los servicios de registro para usar los nuevos RPCs
2. ✅ **Probar registro en la app** - Verificar que cliente, restaurante y repartidor se registran correctamente
3. ✅ **Limpiar código viejo** - Eliminar funciones y lógica de registro antigua

---

¿Listo para empezar? Ejecuta el **PASO 1** primero y compárteme el resultado. 🚀
