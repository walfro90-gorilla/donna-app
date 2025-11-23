# 🎯 SIGNUP REFACTOR - ORDEN DE EJECUCIÓN

## 📋 INSTRUCCIONES

Ejecuta los scripts **en orden numérico** en el SQL Editor de Supabase.

**✅ CORRECCIONES APLICADAS (v2):**
- ✅ Corregida sintaxis de `pg_trigger.tgenabled` (ahora usa `'D'` en lugar de `NOT boolean`)
- ✅ Envueltos todos los `DROP FUNCTION`, `RAISE NOTICE` y `CREATE TRIGGER` en bloques `DO $$`
- ✅ 100% compatible con PostgreSQL 15+ y PostgREST
- ✅ 100% apegado al `DATABASE_SCHEMA.sql` del proyecto

---

## ⚡ PROBLEMA ACTUAL: "Error confirming user"

Si experimentas este error al hacer clic en el enlace de verificación de email:

```
error=server_error&error_code=unexpected_failure&error_description=Error+confirming+user
```

**✅ SOLUCIÓN INMEDIATA:**

```sql
-- 1. EJECUTA ESTE SCRIPT
NUCLEAR_FIX_EMAIL_CONFIRMATION.sql

-- 2. PRUEBA CREANDO UN NUEVO USUARIO
-- Haz clic en el enlace de confirmación

-- 3. SI HAY PROBLEMAS, DIAGNOSTICA
VIEW_EMAIL_CONFIRMATION_LOGS.sql
```

**🔧 QUÉ HACE:**
- Recrea el trigger `handle_email_confirmed` con manejo robusto de errores
- NUNCA rompe la confirmación de email (todos los errores se loguean pero no bloquean)
- Crea tabla `function_logs` para debugging detallado
- Incluye test automático al final

---

## 🧹 FASE 1: LIMPIEZA (Scripts 01-03)

1. `01_cleanup_backup_obsolete.sql` - Hace backup de funciones antiguas
2. `02_cleanup_disable_triggers.sql` ✅ **CORREGIDO** - Desactiva triggers conflictivos
3. `03_cleanup_drop_rpcs.sql` ✅ **CORREGIDO** - Elimina RPCs obsoletos

**⚠️ IMPORTANTE:** No continúes a la Fase 2 hasta verificar que la Fase 1 se ejecutó sin errores.

---

## 🏗️ FASE 2: IMPLEMENTACIÓN (Scripts 04-06)

4. `04_implementation_master_function.sql` - Crea la función maestra de signup
5. `05_implementation_replace_trigger.sql` ✅ **CORREGIDO** - Reemplaza el trigger en auth.users
6. `06_implementation_grant_permissions.sql` ✅ **CORREGIDO** - Configura permisos correctos

**⚠️ IMPORTANTE:** No continúes a la Fase 3 hasta verificar que la Fase 2 se ejecutó sin errores.

---

## ✅ FASE 3: VALIDACIÓN (Scripts 07-08)

7. `07_validation_test_signup.sql` ✅ **CORREGIDO** - Prueba los 3 tipos de signup
8. `08_validation_cleanup_tests.sql` ✅ **CORREGIDO** - Limpia datos de prueba

---

## 🎯 RESULTADO ESPERADO

Después de ejecutar todos los scripts:

✅ Signup de CLIENTE funciona automáticamente
✅ Signup de RESTAURANTE funciona automáticamente
✅ Signup de REPARTIDOR funciona automáticamente
✅ Logs exhaustivos en `debug_user_signup_log`
✅ Rollback automático en caso de error
✅ 13+ funciones obsoletas eliminadas
✅ Triggers conflictivos desactivados

---

## 🚨 ROLLBACK (si algo sale mal)

Si necesitas revertir los cambios, ejecuta:

```sql
-- Restaurar trigger anterior
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created 
  AFTER INSERT ON auth.users
  FOR EACH ROW 
  EXECUTE FUNCTION public.handle_new_user();

-- Reactivar triggers antiguos (si es necesario)
ALTER TABLE public.delivery_agent_profiles ENABLE TRIGGER ALL;
ALTER TABLE public.users ENABLE TRIGGER ALL;
```

---

## 📝 VERIFICACIÓN POST-IMPLEMENTACIÓN

Después de ejecutar todos los scripts, verifica:

1. **Crear un usuario de prueba desde Flutter:**
   ```dart
   await supabase.auth.signUp(
     email: 'test@test.com',
     password: 'Test123!',
     data: {'role': 'cliente', 'name': 'Test User'}
   );
   ```

2. **Verificar logs:**
   ```sql
   SELECT * FROM debug_user_signup_log 
   WHERE email = 'test@test.com' 
   ORDER BY created_at DESC;
   ```

3. **Verificar que se crearon todos los registros:**
   ```sql
   SELECT 
     u.id, u.email, u.role,
     cp.user_id as has_client_profile,
     a.account_type,
     up.user_id as has_preferences
   FROM users u
   LEFT JOIN client_profiles cp ON cp.user_id = u.id
   LEFT JOIN accounts a ON a.user_id = u.id
   LEFT JOIN user_preferences up ON up.user_id = u.id
   WHERE u.email = 'test@test.com';
   ```

---

✅ **Todo listo. Comienza ejecutando el script 01.**
