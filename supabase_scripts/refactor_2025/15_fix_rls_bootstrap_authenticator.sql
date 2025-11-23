-- ===================================================================
-- FIX OPCIONAL: Habilitar bootstrap de perfiles/usuarios por el rol 'authenticator'
-- Úsalo SOLO si el diagnóstico (14_diag_signup_stack_v2.sql) mostró errores
-- de RLS cuando se ejecuta como role authenticator.
-- Este fix NO toca triggers en auth.users.
-- ===================================================================

-- 0) Precondición de seguridad: confirmar entorno
-- select current_user; -- Debe ser un rol admin (p.ej. postgres)

-- 1) Asegurar RLS habilitado (no cambia estado si ya lo está)
alter table if exists public.client_profiles enable row level security;
alter table if exists public.users enable row level security;

-- 2) Política mínima para permitir INSERT/UPDATE desde 'authenticator' SOLO para bootstrap
--    Nota: 'authenticator' es usado internamente por GoTrue. No es expuesto al cliente.

-- 2.1) client_profiles
drop policy if exists rls_bootstrap_insert_client_profiles on public.client_profiles;
create policy rls_bootstrap_insert_client_profiles
  on public.client_profiles
  for insert
  to authenticator
  with check (true);

drop policy if exists rls_bootstrap_update_client_profiles on public.client_profiles;
create policy rls_bootstrap_update_client_profiles
  on public.client_profiles
  for update
  to authenticator
  using (true)
  with check (true);

-- 2.2) users (tabla espejo de tu app si aplica)
drop policy if exists rls_bootstrap_insert_users on public.users;
create policy rls_bootstrap_insert_users
  on public.users
  for insert
  to authenticator
  with check (true);

drop policy if exists rls_bootstrap_update_users on public.users;
create policy rls_bootstrap_update_users
  on public.users
  for update
  to authenticator
  using (true)
  with check (true);

-- 3) Grants explícitos por si faltan (políticas gobiernan RLS; grants gobiernan privilegios base)
grant insert, update on table public.client_profiles to authenticator;
grant insert, update on table public.users to authenticator;

-- 4) Verificación rápida
-- select * from pg_policies where schemaname='public' and tablename in ('client_profiles','users') order by tablename, polname;

-- 5) Nota de endurecimiento posterior (opcional):
--    Una vez estabilizado el registro, puedes refinar estas políticas para
--    permitir únicamente filas donde user_id = NEW.id, pero eso requiere que
--    el trigger pase el id por contexto. Alternativamente, migrar la función
--    a SECURITY DEFINER para no depender de 'authenticator'.

-- ===================================================================
-- FIN FIX OPCIONAL (RLS bootstrap authenticator)
-- ===================================================================
