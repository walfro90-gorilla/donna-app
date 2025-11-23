# 🚨 SOLUCIÓN: ERROR 500 "Database error saving new user"

## 📋 PROBLEMA IDENTIFICADO

Cuando un usuario intenta registrarse, falla con error:

```
POST /auth/v1/signup 500 (Internal Server Error)
{"code":"unexpected_failure","message":"Database error saving new user"}
```

### 🔍 CAUSA RAÍZ

El trigger `on_auth_user_created` que se ejecuta automáticamente al crear un usuario en `auth.users` está fallando porque:

1. **La función `ensure_client_profile_and_account()` intenta insertar una columna `status` que NO EXISTE en la tabla `client_profiles`**

2. **Schema real de `client_profiles`:**
   ```sql
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
     -- ❌ NO TIENE COLUMNA 'status'
   );
   ```

3. **Código incorrecto en `ensure_client_profile_and_account()`:**
   ```sql
   INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
   VALUES (p_user_id, 'active', v_now, v_now)
   --                  ^^^^^^^^ ❌ Esta columna NO existe
   ```

---

## ✅ SOLUCIÓN

### **Paso 1: Ejecutar el script de corrección**

📄 **Archivo:** `supabase_scripts/refactor_2025/FIX_handle_new_user_trigger.sql`

**Qué hace:**
- ✅ Corrige la función `ensure_client_profile_and_account()` para usar SOLO las columnas reales
- ✅ Actualiza `handle_new_user()` con mejor manejo de errores
- ✅ Recrea el trigger `on_auth_user_created`
- ✅ Agrega logging para debugging

**Cómo ejecutar:**
1. Abre Supabase Dashboard
2. Ve a `SQL Editor`
3. Copia y pega el contenido de `FIX_handle_new_user_trigger.sql`
4. Haz click en `RUN`

---

### **Paso 2: Probar el registro**

1. **Intenta crear un nuevo usuario desde la app**
   - Email: `test@example.com`
   - Password: `password123`
   - Name: `Test User`
   - Phone: `+525512345678`

2. **Verifica que se crearon los registros:**
   ```sql
   -- Usuario en auth
   SELECT id, email, created_at 
   FROM auth.users 
   WHERE email = 'test@example.com';
   
   -- Usuario en public.users
   SELECT id, email, name, role 
   FROM public.users 
   WHERE email = 'test@example.com';
   
   -- Perfil de cliente
   SELECT * 
   FROM public.client_profiles 
   WHERE user_id = (SELECT id FROM auth.users WHERE email = 'test@example.com');
   
   -- Cuenta financiera
   SELECT * 
   FROM public.accounts 
   WHERE user_id = (SELECT id FROM auth.users WHERE email = 'test@example.com');
   
   -- Preferencias
   SELECT * 
   FROM public.user_preferences 
   WHERE user_id = (SELECT id FROM auth.users WHERE email = 'test@example.com');
   ```

3. **Checa logs de debug:**
   ```sql
   SELECT * 
   FROM public.debug_user_signup_log 
   ORDER BY created_at DESC 
   LIMIT 10;
   ```

---

## 🔄 FLUJO DE REGISTRO CORREGIDO

### **Para CLIENTES (registro normal):**

```
1. Usuario llena formulario de registro
   ↓
2. Flutter llama: supabase.auth.signUp(email, password, {name, phone})
   ↓
3. Supabase crea usuario en auth.users
   ↓
4. Trigger on_auth_user_created se ejecuta automáticamente
   ↓
5. Función handle_new_user() llama ensure_client_profile_and_account()
   ↓
6. Se crean automáticamente:
   ✅ public.users (role='cliente')
   ✅ public.client_profiles
   ✅ public.accounts (account_type='client', balance=0)
   ✅ public.user_preferences
   ↓
7. Usuario puede iniciar sesión inmediatamente
```

### **Para RESTAURANTES/REPARTIDORES:**

```
1. Usuario llena formulario especializado
   ↓
2. Flutter llama: supabase.auth.signUp(email, password)
   ↓
3. Trigger crea perfil básico de cliente (role='cliente')
   ↓
4. Flutter inmediatamente llama:
   - register_restaurant() o
   - register_delivery_agent()
   ↓
5. RPC cambia el role y crea perfil especializado:
   ✅ Actualiza role en public.users
   ✅ Crea restaurants o delivery_agent_profiles
   ✅ Mantiene la cuenta financiera
```

---

## 🐛 DEBUGGING

### **Si el error persiste:**

1. **Revisa los logs de Postgres:**
   - Supabase Dashboard → Database → Logs → Postgres Logs
   - Busca errores con timestamp reciente

2. **Verifica que el trigger existe:**
   ```sql
   SELECT 
     trigger_name,
     event_manipulation,
     action_statement
   FROM information_schema.triggers
   WHERE event_object_schema = 'auth'
     AND event_object_table = 'users';
   ```

3. **Prueba la función manualmente:**
   ```sql
   -- Crear un usuario de prueba en auth.users (reemplaza con ID real)
   SELECT public.ensure_client_profile_and_account('UUID-AQUI');
   ```

4. **Verifica el schema de client_profiles:**
   ```sql
   SELECT 
     column_name,
     data_type,
     is_nullable,
     column_default
   FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name = 'client_profiles'
   ORDER BY ordinal_position;
   ```

---

## 📝 CAMBIOS REALIZADOS

### ✅ **Función `ensure_client_profile_and_account()`:**
- Removida columna `status` inexistente
- Agregado manejo de `email`, `name`, `phone` desde `auth.users`
- Mejorado manejo de roles especializados
- Agregado retorno de datos útiles

### ✅ **Función `handle_new_user()`:**
- Agregado manejo de excepciones con logging
- Insertado registro en `debug_user_signup_log` para debugging

### ✅ **Trigger `on_auth_user_created`:**
- Recreado con nombre consistente
- Limpiado triggers duplicados

---

## 🎯 PRÓXIMOS PASOS

1. ✅ **Ejecutar `FIX_handle_new_user_trigger.sql`**
2. ✅ **Probar registro de cliente desde la app**
3. ✅ **Verificar que todos los registros se crean correctamente**
4. ⏳ **Continuar con la refactorización (steps 12-15)**

---

## 📞 SOPORTE

Si el problema persiste:
1. Copia el error COMPLETO de los logs de Postgres
2. Ejecuta la query de debug: `SELECT * FROM debug_user_signup_log ORDER BY created_at DESC LIMIT 10;`
3. Comparte ambos resultados para análisis
