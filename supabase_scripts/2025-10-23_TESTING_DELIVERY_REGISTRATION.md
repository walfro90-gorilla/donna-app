# 🧪 Testing Guide: Delivery Agent Registration

## Pre-requisitos
1. Corre el script principal en Supabase SQL Editor:
   ```
   2025-10-23_fix_client_trigger_and_registration.sql
   ```

## Qué hace el script

### Parte 1: Trigger inteligente
- ✅ Actualiza el trigger `handle_new_user` para que **solo** cree perfiles de cliente si el usuario NO tiene un role especializado
- ✅ Añade un pequeño delay (0.1s) para permitir que RPCs especializados corran primero
- ✅ Valida el role antes de crear `client_profiles`

### Parte 2: Función defensiva
- ✅ Actualiza `ensure_client_profile_and_account` para que **no sobrescriba** roles especializados (restaurant, delivery_agent, admin)
- ✅ Retorna `{skipped: true}` si el usuario ya tiene un role especializado

### Parte 3: RPC atómico completo
- ✅ Crea el RPC `register_delivery_agent_atomic` que maneja todo el registro de delivery agents
- ✅ Limpia cualquier dato de cliente creado por el trigger (race condition)
- ✅ Fuerza role='delivery_agent' explícitamente
- ✅ Crea todos los registros necesarios:
  - `users` (role='delivery_agent')
  - `delivery_agent_profiles`
  - `accounts` (account_type='delivery_agent')
  - `user_preferences`

## Cómo validar

### 1️⃣ Verificar que el RPC existe
```sql
SELECT p.proname, pg_get_function_identity_arguments(p.oid) args
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname = 'register_delivery_agent_atomic';
```

Debe retornar 1 fila con todos los parámetros (21 en total).

### 2️⃣ Verificar que el trigger está actualizado
```sql
SELECT pg_get_triggerdef(oid) 
FROM pg_trigger 
WHERE tgname = 'trg_handle_new_user_on_auth_users';
```

Debe mostrar que el trigger está vinculado a `public.handle_new_user()`.

### 3️⃣ Limpiar datos de prueba anteriores
```sql
-- Elimina el usuario de prueba anterior (si existe)
DELETE FROM auth.users WHERE email = 'test-delivery@example.com';
DELETE FROM public.users WHERE email = 'test-delivery@example.com';
```

### 4️⃣ Probar desde la app
1. Abre el formulario de registro de delivery agent
2. Llena todos los campos
3. Registra un nuevo delivery agent

### 5️⃣ Verificar los datos creados
```sql
-- Debe retornar role='delivery_agent'
SELECT id, email, name, role 
FROM public.users 
WHERE email = '<email-que-usaste>';

-- Debe retornar 1 fila (perfil de delivery agent)
SELECT user_id, status, vehicle_type 
FROM public.delivery_agent_profiles 
WHERE user_id = (SELECT id FROM public.users WHERE email = '<email-que-usaste>');

-- NO debe existir client_profiles
SELECT * FROM public.client_profiles 
WHERE user_id = (SELECT id FROM public.users WHERE email = '<email-que-usaste>');
-- Debe retornar 0 filas

-- Debe retornar 1 cuenta tipo 'delivery_agent'
SELECT user_id, account_type, balance 
FROM public.accounts 
WHERE user_id = (SELECT id FROM public.users WHERE email = '<email-que-usaste>');
-- Debe ser: account_type='delivery_agent', balance=0.0

-- Debe retornar 1 fila de preferencias
SELECT user_id, has_seen_onboarding 
FROM public.user_preferences 
WHERE user_id = (SELECT id FROM public.users WHERE email = '<email-que-usaste>');
```

## Resultados esperados ✅

Después de registrar un delivery agent:

| Tabla | Debe existir | Role/Type correcto | NO debe existir |
|-------|--------------|-------------------|-----------------|
| `auth.users` | ✅ | - | - |
| `public.users` | ✅ | role='delivery_agent' | - |
| `delivery_agent_profiles` | ✅ | status='pending' | - |
| `accounts` | ✅ | account_type='delivery_agent' | account_type='client' ❌ |
| `user_preferences` | ✅ | - | - |
| `client_profiles` | ❌ NO | - | ✅ NO debe existir |

## Troubleshooting

### Problema: Sigue creando client_profiles
**Solución:** Verifica que el trigger se actualizó correctamente:
```sql
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'handle_new_user';
```
Debe incluir la lógica de verificación de role.

### Problema: Error "function does not exist"
**Solución:** El RPC no se creó. Corre el script completo de nuevo.

### Problema: Sigue teniendo role='client'
**Solución:** El RPC no está forzando el role. Verifica que la línea 166 del script diga:
```sql
role = 'delivery_agent',  -- SIEMPRE forzar delivery_agent
```

## Limpieza después de testing
```sql
-- Eliminar usuario de prueba completo
DELETE FROM public.user_preferences WHERE user_id IN (SELECT id FROM public.users WHERE email LIKE 'test-%');
DELETE FROM public.accounts WHERE user_id IN (SELECT id FROM public.users WHERE email LIKE 'test-%');
DELETE FROM public.delivery_agent_profiles WHERE user_id IN (SELECT id FROM public.users WHERE email LIKE 'test-%');
DELETE FROM public.client_profiles WHERE user_id IN (SELECT id FROM public.users WHERE email LIKE 'test-%');
DELETE FROM public.users WHERE email LIKE 'test-%';
DELETE FROM auth.users WHERE email LIKE 'test-%';
```
