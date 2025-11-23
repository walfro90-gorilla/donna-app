# Instrucciones: Registro Atómico de Delivery Agent

## 🎯 Objetivo
Crear un RPC profesional, limpio y atómico para el registro completo de delivery agents, sin parches ni soluciones temporales.

## 📋 Lo que hace el RPC `register_delivery_agent_atomic`

El RPC crea **TODOS** los registros necesarios en una sola transacción atómica:

1. ✅ Registro en `auth.users` (ya creado por Supabase Auth antes de llamar al RPC)
2. ✅ Registro en tabla `users` con `role='delivery_agent'`
3. ✅ Registro en tabla `delivery_agent_profiles` con todos los datos del vehículo y documentos
4. ✅ Registro en tabla `accounts` con `account_type='delivery_agent'`
5. ✅ Registro en tabla `user_preferences` (para manejar onboarding y alertas)

## 🔧 Pasos para implementar

### 1. Ejecutar la migración en Supabase

Corre el siguiente archivo SQL en tu consola de Supabase:

```
supabase_scripts/2025-10-23_register_delivery_agent_atomic.sql
```

Este archivo:
- ✅ Elimina cualquier versión anterior del RPC (limpieza completa)
- ✅ Crea la función `register_delivery_agent_atomic` con SECURITY DEFINER
- ✅ Otorga permisos correctos (anon, authenticated, service_role)
- ✅ Es idempotente (puede ejecutarse múltiples veces sin romper nada)

### 2. Verificar que el RPC fue creado correctamente

Ejecuta esta query en Supabase SQL Editor:

```sql
SELECT 
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as parameters,
  p.prosecdef as is_security_definer
FROM pg_proc p 
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' 
  AND p.proname = 'register_delivery_agent_atomic';
```

Deberías ver:
- `function_name`: `register_delivery_agent_atomic`
- `is_security_definer`: `true`
- `parameters`: Todos los 21 parámetros listados

### 3. La app ya está lista

Los cambios en el código de Flutter ya están hechos:
- ✅ `lib/core/supabase/rpc_names.dart` → constante `registerDeliveryAgentAtomic`
- ✅ `lib/screens/public/delivery_agent_registration_screen.dart` → usa el nuevo RPC

## 🧪 Probar el registro

1. Ve a la pantalla de registro de delivery agent en la app
2. Llena todos los campos del formulario
3. Envía el formulario
4. Verifica en Supabase que se crearon los registros en:
   - `users` (con `role='delivery_agent'`)
   - `delivery_agent_profiles`
   - `accounts` (con `account_type='delivery_agent'`)
   - `user_preferences`

## 🔍 Queries de verificación

### Ver el usuario creado
```sql
SELECT id, email, name, role, phone, address 
FROM users 
WHERE email = 'tu-email-de-prueba@example.com';
```

### Ver el perfil de delivery agent
```sql
SELECT * 
FROM delivery_agent_profiles 
WHERE user_id = (SELECT id FROM users WHERE email = 'tu-email-de-prueba@example.com');
```

### Ver la cuenta financiera
```sql
SELECT * 
FROM accounts 
WHERE user_id = (SELECT id FROM users WHERE email = 'tu-email-de-prueba@example.com')
  AND account_type = 'delivery_agent';
```

### Ver las preferencias
```sql
SELECT * 
FROM user_preferences 
WHERE user_id = (SELECT id FROM users WHERE email = 'tu-email-de-prueba@example.com');
```

## ✨ Características del RPC

- ✅ **Atómico**: Todo o nada (transacción única)
- ✅ **Idempotente**: Puede ejecutarse múltiples veces sin duplicar datos
- ✅ **SECURITY DEFINER**: Ejecuta con permisos de propietario de la función
- ✅ **Respuesta estándar**: `{success: bool, data: {...}, error: string?}`
- ✅ **Manejo de errores**: Captura excepciones y retorna error legible
- ✅ **Siguiendo el patrón exitoso**: Basado en `register_restaurant_v2`

## 🚨 Notas importantes

1. **NO usar RPCs antiguos**: Este RPC reemplaza completamente cualquier versión anterior
2. **Verificar permisos**: El RPC tiene `SECURITY DEFINER`, lo que significa que ejecuta con permisos elevados
3. **Limpiar data de prueba**: Elimina manualmente registros de prueba antes de probar nuevamente
4. **Role correcto**: El RPC normaliza automáticamente el role a `delivery_agent`

## 📞 Soporte

Si hay algún error:
1. Revisa los logs de la consola del navegador (busca `[DELIVERY_REG]`)
2. Ejecuta las queries de verificación arriba
3. Verifica que el RPC existe y tiene permisos correctos
