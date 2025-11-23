# ⚠️ INSTRUCCIONES MANUALES: CREAR TRIGGER EN auth.users

## 🚨 **POR QUÉ ES NECESARIO HACER ESTO MANUAL**

El SQL Editor de Supabase **NO tiene permisos** para crear triggers en la tabla `auth.users` porque:
- `auth.users` es propiedad del usuario `supabase_auth_admin`
- Por seguridad, Supabase restringe modificaciones directas a tablas de autenticación
- Solo el superusuario `postgres` puede modificar triggers en `auth.users`

---

## 📋 **OPCIÓN 1: USAR LA CONSOLA DE SUPABASE (Recomendado)**

### **Paso 1: Abrir SQL Editor con permisos elevados**

1. Ve a tu proyecto en **Supabase Dashboard**
2. Navega a **SQL Editor** (menú lateral izquierdo)
3. Click en **"New Query"**

### **Paso 2: Ejecutar este SQL con permisos de superusuario**

Copia y pega exactamente este código:

```sql
-- ============================================================================
-- CONFIGURAR TRIGGER EN auth.users (REQUIERE PERMISOS DE POSTGRES)
-- ============================================================================

-- 1. Eliminar triggers obsoletos
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS handle_new_user ON auth.users;
DROP TRIGGER IF EXISTS trg_after_insert_auth_user ON auth.users;
DROP TRIGGER IF EXISTS create_public_user_on_signup ON auth.users;

-- 2. Crear el nuevo trigger que ejecuta master_handle_signup()
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.master_handle_signup();

-- 3. Agregar comentario
COMMENT ON TRIGGER on_auth_user_created ON auth.users IS 
  'Master signup trigger. Se ejecuta automáticamente cuando Supabase Auth crea un usuario.';

-- 4. Verificar que se creó correctamente
SELECT 
  t.tgname AS trigger_name,
  c.relname AS table_name,
  p.proname AS function_name,
  CASE 
    WHEN t.tgenabled = 'O' THEN 'enabled'
    WHEN t.tgenabled = 'D' THEN 'disabled'
    ELSE 'unknown'
  END AS status
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE n.nspname = 'auth'
  AND c.relname = 'users'
  AND t.tgname = 'on_auth_user_created';
```

### **Paso 3: Verificar el resultado**

Deberías ver un resultado como este:

```
trigger_name         | table_name | function_name         | status
---------------------|------------|-----------------------|---------
on_auth_user_created | users      | master_handle_signup  | enabled
```

✅ Si ves este resultado, el trigger está configurado correctamente.

---

## 📋 **OPCIÓN 2: USAR SUPABASE CLI** (Alternativa)

Si prefieres usar Supabase CLI localmente:

### **Paso 1: Instalar Supabase CLI**

```bash
npm install -g supabase
```

### **Paso 2: Login y link al proyecto**

```bash
supabase login
supabase link --project-ref TU_PROJECT_REF
```

### **Paso 3: Crear migration**

```bash
supabase migration new create_auth_trigger
```

### **Paso 4: Editar el archivo de migración**

Copia el SQL del **Paso 2 de la Opción 1** en el archivo de migración generado.

### **Paso 5: Aplicar la migración**

```bash
supabase db push
```

---

## 📋 **OPCIÓN 3: CONTACTAR SOPORTE DE SUPABASE** (Si las opciones anteriores fallan)

Si ninguna de las opciones anteriores funciona:

1. Ve a **Supabase Support** en tu dashboard
2. Abre un ticket explicando:
   - Necesitas crear un trigger en `auth.users`
   - El trigger debe ejecutar `public.master_handle_signup()`
   - Proporciona el SQL del **Paso 2 de la Opción 1**

---

## ✅ **DESPUÉS DE CONFIGURAR EL TRIGGER MANUALMENTE**

Una vez que hayas creado el trigger exitosamente:

1. **Elimina las funciones obsoletas** ejecutando este SQL en el editor normal:

```sql
DO $$
BEGIN
  DROP FUNCTION IF EXISTS public.handle_new_user CASCADE;
  DROP FUNCTION IF EXISTS public._trg_after_insert_auth_user CASCADE;
  DROP FUNCTION IF EXISTS public.create_public_user_on_signup CASCADE;
  
  RAISE NOTICE '✅ Funciones obsoletas eliminadas';
END $$;
```

2. **Continúa con el script 06**:
   ```
   06_implementation_grant_permissions.sql
   ```

---

## 🔍 **VERIFICAR QUE TODO FUNCIONA**

Después de configurar el trigger, prueba crear un usuario:

```sql
-- Test signup (simula un registro desde Flutter)
SELECT auth.uid(); -- Debería ser NULL si no estás autenticado

-- Luego, desde Flutter, intenta registrar un usuario normalmente
-- El trigger debería crear automáticamente:
-- ✅ public.users
-- ✅ client_profiles (si es cliente)
-- ✅ accounts
-- ✅ user_preferences
```

---

## 📞 **NECESITAS AYUDA?**

Si tienes problemas con alguno de estos pasos, comparte:
- El mensaje de error exacto
- Qué opción intentaste usar
- Capturas de pantalla del Supabase Dashboard

---

## 🎯 **RESUMEN**

| Opción | Dificultad | Recomendado |
|--------|-----------|-------------|
| Opción 1: Supabase Dashboard SQL Editor | Fácil | ✅ SÍ |
| Opción 2: Supabase CLI | Media | Solo si usas CLI |
| Opción 3: Soporte Supabase | Fácil | Si fallan las demás |

**Intenta la Opción 1 primero.** Es la más directa y debería funcionar sin problemas. 🚀
