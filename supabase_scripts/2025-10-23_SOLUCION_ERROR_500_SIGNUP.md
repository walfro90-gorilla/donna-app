# 🔴 ERROR 500: "Database error saving new user"

## Diagnóstico

**Síntoma:**  
Al registrar un delivery agent, Supabase.auth.signUp() falla con error 500 "Database error saving new user".

**Causa raíz:**  
El trigger `trg_handle_new_user_on_auth_users` en la tabla `auth.users` se ejecuta automáticamente cuando Supabase crea un nuevo usuario. Este trigger intenta crear un perfil de cliente (`client_profiles` + cuenta tipo 'client') para **TODOS** los usuarios nuevos, sin importar su role.

Cuando intentamos registrar un delivery agent:
1. Supabase crea el `auth.user`
2. El trigger se dispara automáticamente
3. Intenta crear `client_profiles` y `accounts` tipo 'client'
4. El RPC `register_delivery_agent_atomic` todavía no se ha ejecutado
5. El usuario queda con role 'client' en vez de 'delivery_agent'
6. **Esto causa conflictos y errores 500**

## Solución

**Desactivar el trigger en `auth.users` completamente.**

Los RPCs atómicos ya crean todos los registros necesarios según el role correcto:
- `register_restaurant_v2` → crea restaurantes con role 'restaurant'
- `register_delivery_agent_atomic` → crea delivery agents con role 'delivery_agent'
- Clientes normales → se pueden manejar con un endpoint separado o signup estándar

El trigger es redundante y causa conflictos.

## Archivo SQL a ejecutar

```sql
-- Ver archivo: 2025-10-23_disable_auth_trigger.sql
```

Este script:
1. Elimina el trigger `trg_handle_new_user_on_auth_users`
2. Mantiene la función `handle_new_user()` por compatibilidad pero sin trigger
3. Muestra los triggers activos en `auth.users` para verificación

## Después de ejecutar

1. Correr el script `2025-10-23_disable_auth_trigger.sql` en Supabase
2. Verificar que el trigger fue eliminado
3. Intentar registrar un delivery agent nuevamente
4. El RPC `register_delivery_agent_atomic` creará todos los registros correctamente con role 'delivery_agent'

## Flujo correcto post-fix

```
Usuario llena formulario
  ↓
Frontend llama Supabase.auth.signUp()
  ↓
Supabase crea auth.user (SIN triggers automáticos)
  ↓
Frontend llama register_delivery_agent_atomic RPC
  ↓
RPC crea atómicamente:
  - users (role='delivery_agent')
  - delivery_agent_profiles
  - accounts (account_type='delivery_agent')
  - user_preferences
  ↓
✅ Usuario registrado correctamente
```

## Notas importantes

- Los triggers en `public.users` y `public.accounts` siguen activos (solo para clientes regulares)
- Los RPCs atómicos siguen siendo la fuente de verdad para registros especializados
- El trigger en `auth.users` era el único problemático porque ejecutaba ANTES de que pudiéramos controlar el role
