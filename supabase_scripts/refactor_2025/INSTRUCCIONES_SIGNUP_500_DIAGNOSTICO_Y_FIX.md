# Guía quirúrgica: Error 500 en signup (Database error saving new user)

Objetivo: No adivinar. Ver la definición real en tu BD, aplicar el fix mínimo y verificar con logs.

Fuente de verdad del esquema: `supabase_scripts/DATABASE_SCHEMA.sql` (no se ejecuta; solo referencia de columnas).

## 1) Diagnóstico (obligatorio)

En el SQL Editor de Supabase, ejecuta:

```
supabase_scripts/refactor_2025/DIAGNOSTIC_signup_root_cause.sql
```

Comparte los resultados (o confirma visualmente):
- ¿La función `public.ensure_client_profile_and_account(uuid)` incluye email al upsert de `public.users`?
- ¿`public.users.email` es NOT NULL y UNIQUE? (según tu schema, sí)
- ¿El trigger sobre `auth.users` llama a `public.handle_new_user()`?
- ¿`client_profiles` tiene `status text NOT NULL DEFAULT 'active'`?
- ¿El CHECK de `accounts.account_type` incluye `'client'`?

## 2) Fix definitivo (seguro e idempotente)

Ejecuta:

```
supabase_scripts/refactor_2025/FINAL_SIGNUP_ROOT_FIX_and_LOG.sql
```

Qué hace exactamente:
1. Garantiza que el CHECK de `accounts.account_type` incluye `'client'`.
2. Reemplaza `ensure_client_profile_and_account(uuid)` para que:
   - Lea `email` desde `auth.users`.
   - Upserte `public.users` con `(id, email, role='cliente')` y timestamps.
   - Cree/actualice `public.client_profiles` con `status='active'`.
   - Cree (si falta) `public.accounts` con `account_type='client'` y `balance=0`.
   - Escriba logs en `public.debug_user_signup_log`.
3. Endurece `public.handle_new_user()` para que NUNCA lance error (no rompe el signup) y registre todo en logs.

Permisos: No toca el trigger en `auth.users` (evita `must be owner of relation users`). Si ya existe y apunta a `public.handle_new_user()`, tomará la nueva definición automáticamente.

## 3) Verificación

1. Intenta registrarte de nuevo desde la app.
2. Consulta logs:

```sql
SELECT * FROM public.debug_user_signup_log
ORDER BY created_at DESC
LIMIT 50;
```

Deberías ver eventos `TRIGGER_FIRED` y `SUCCESS` con `account_id`.

## 4) Si aún falla

Pega aquí:
- Resultado completo de `DIAGNOSTIC_signup_root_cause.sql`.
- Últimos 50 logs de `debug_user_signup_log`.

Con eso te daré el ajuste exacto (p. ej., si tu trigger usa otro nombre, o si el CHECK de `accounts` difiere).

## Notas de alineación

- Roles válidos en `public.users.role`: `'cliente','restaurante','repartidor','admin'`.
- `public.users.email` es NOT NULL UNIQUE: cualquier upsert debe incluir `email`.
- `client_profiles.status` existe y debe rellenarse con `'active'` al crear.
- `accounts.account_type` debe permitir `'client'`.
