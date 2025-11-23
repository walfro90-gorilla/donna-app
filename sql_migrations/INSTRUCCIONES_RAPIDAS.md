# 🚀 Instrucciones Rápidas - Fix Error Status

## ❌ Problema Actual

```
record "old" has no field "status" (42703)
create_restaurant_public error: Could not find the function
```

## ✅ Solución Rápida (1 archivo)

Ejecuta **SOLO** este archivo en tu base de datos Supabase:

```bash
FIX_STATUS_ERROR_EJECUTIVO.sql
```

### Cómo ejecutarlo en Supabase:

1. **Abre el SQL Editor en Supabase Dashboard**
   - Ve a tu proyecto en https://supabase.com
   - Click en "SQL Editor" en el menú lateral

2. **Copia y pega el contenido completo de:**
   ```
   FIX_STATUS_ERROR_EJECUTIVO.sql
   ```

3. **Click en "Run"** (botón verde abajo a la derecha)

4. **Espera 5 segundos** - verás mensajes como:
   ```
   ✅ Eliminado: client_profiles.xxx
   ✅ Funciones legacy eliminadas
   ✅ FIX COMPLETADO EXITOSAMENTE
   ```

5. **Refresca tu app Flutter** y prueba registrar un restaurante

---

## 📋 Qué hace este script

### ✅ Elimina:
- Triggers problemáticos en `client_profiles` que causan el error
- Triggers problemáticos en `users` (excepto `updated_at`)
- Funciones legacy: `create_user_profile_public`, `create_restaurant_public`, `create_account_public`
- Funciones de sync de status que causan conflictos

### ✅ NO toca:
- ❌ No modifica ninguna tabla
- ❌ No elimina datos
- ❌ No afecta las funciones v2 que sí funcionan
- ❌ No requiere downtime

### ✅ Es seguro porque:
- Usa `DROP IF EXISTS` (no falla si no existe)
- Incluye diagnóstico antes y después
- Muestra exactamente qué elimina
- Toma menos de 5 segundos

---

## 🎯 Después de ejecutar

Tu app podrá usar estas funciones:
- ✅ `ensure_user_profile_v2()` - Crear/actualizar usuarios
- ✅ `register_restaurant_v2()` - Registrar restaurantes (ESTA ES LA QUE NECESITAS)
- ✅ `register_delivery_agent_atomic()` - Registrar repartidores
- ✅ `create_order_safe()` - Crear órdenes
- ✅ `accept_order()` - Aceptar órdenes
- ✅ Todas las demás funciones del sistema

---

## 🔍 Verificación Manual (opcional)

Si quieres verificar que funcionó:

```sql
-- Ver triggers restantes en client_profiles (debería ser 0)
SELECT tgname FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname = 'client_profiles' AND NOT t.tgisinternal;

-- Ver funciones v2 disponibles
SELECT proname FROM pg_proc 
WHERE pronamespace = 'public'::regnamespace 
  AND proname LIKE '%_v2'
ORDER BY proname;
```

---

## 📞 Si aún tienes problemas

1. Verifica que ejecutaste el script completo (no solo una parte)
2. Revisa los logs del script - debe decir "FIX COMPLETADO EXITOSAMENTE"
3. Refresca la página de tu app Flutter
4. Intenta registrar un restaurante de nuevo
5. Si sigue fallando, revisa los logs de la app Flutter para ver qué función está llamando

---

## 📚 Archivos Adicionales (solo si lo necesitas)

Si quieres entender más o hacer setup completo:

- `01_schema_tables.sql` - Crear schema completo (solo si es DB nueva)
- `02_rls_policies.sql` - Configurar permisos (solo si es DB nueva)
- `03_functions_rpcs.sql` - Crear funciones v2 (solo si no existen)
- `04_drop_problematic_triggers.sql` - Versión detallada del fix
- `05_cleanup_unused_functions.sql` - Limpieza adicional
- `README.md` - Documentación completa

Pero para resolver tu problema actual **solo necesitas `FIX_STATUS_ERROR_EJECUTIVO.sql`**
