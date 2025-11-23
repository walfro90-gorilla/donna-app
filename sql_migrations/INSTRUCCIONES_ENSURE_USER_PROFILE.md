# ✅ Fix del Error: "users_role_check constraint violation"

## 🎯 Problema Identificado

El error ocurre porque:

1. **Frontend** usa `role = 'restaurant'` (inglés) ✅
2. **Base de datos** acepta `'restaurant'` en el CHECK constraint ✅
3. **Falta la RPC** `ensure_user_profile_public()` que normaliza roles (español → inglés)
4. Cuando el RPC no existe, el código hace INSERT directo y falla

## 📋 Solución

Ejecutar el script SQL que crea la RPC faltante:

### **Archivo a ejecutar:**
```
sql_migrations/CREATE_ENSURE_USER_PROFILE_RPC.sql
```

### **Qué hace este script:**

1. ✅ Crea la RPC `ensure_user_profile_public()` con normalización automática de roles:
   - `'restaurante'` → `'restaurant'`
   - `'repartidor'` → `'delivery_agent'`
   - `'cliente'` → `'client'`
   - etc.

2. ✅ Hace INSERT/UPDATE idempotente en `public.users`
3. ✅ Respeta el CHECK constraint de la tabla
4. ✅ Maneja casos edge (emails vacíos, roles duplicados, etc.)
5. ✅ Loggea operaciones para debugging

---

## 🚀 Pasos para Ejecutar

### 1. Abrir Supabase SQL Editor
   - Ve a: https://supabase.com/dashboard/project/[tu-project-id]/sql

### 2. Copiar y pegar el contenido de:
   ```
   sql_migrations/CREATE_ENSURE_USER_PROFILE_RPC.sql
   ```

### 3. Ejecutar (Run)
   - Tiempo de ejecución: < 5 segundos
   - ✅ Safe to run: no modifica datos, solo crea función

### 4. Verificar el resultado
   Deberías ver:
   ```
   ========================================
   ✅ RPC ensure_user_profile_public CREADA CORRECTAMENTE
   ========================================
   ```

---

## ✅ Después de Ejecutar

1. **NO hay cambios de código necesarios** - el frontend ya está configurado correctamente
2. Hacer **Hot Restart** en Dreamflow
3. Probar registro de restaurante nuevamente
4. El flujo completo debería funcionar:
   - ✅ Crea usuario en `auth.users`
   - ✅ Crea perfil en `public.users` con `role = 'restaurant'`
   - ✅ Crea restaurante en `public.restaurants`
   - ✅ Crea cuenta en `public.accounts`

---

## 🔍 Validación

Después del registro, verifica en Supabase que se crearon:

1. **auth.users**: nuevo usuario con email confirmado
2. **public.users**: perfil con `role = 'restaurant'`
3. **public.restaurants**: restaurante con `status = 'pending'`
4. **public.accounts**: cuenta con `account_type = 'restaurant'` y `balance = 0`

---

## ⚠️ Notas

- Este script es **idempotente**: puede ejecutarse múltiples veces sin problemas
- No afecta registros existentes
- Solo crea la función faltante que el frontend ya está llamando
