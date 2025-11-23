-- Auditoría de funciones, triggers y permisos relacionados con registro de cliente
-- IMPORTANTE: Este script es SOLO LECTURA. No modifica nada.
-- Compatible con el editor SQL de Supabase (sin metacomandos tipo \echo)

-- 0) Contexto de base de datos
select current_setting('server_version')       as postgres_version,
       current_schema()                        as current_schema,
       current_setting('search_path')          as search_path;

-- 1) Inventario de funciones clave
select n.nspname                                as schema,
       p.proname                                as name,
       pg_get_function_identity_arguments(p.oid) as args,
       p.prokind                                as kind,         -- f=function, p=procedure
       p.prosecdef                              as security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'ensure_user_profile_public',
    'handle_new_user_signup_v2',
    'handle_auth_user_created'
  )
order by p.proname;

-- 1b) Definiciones de funciones (código fuente actual)
select 'ensure_user_profile_public' as fn, pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'ensure_user_profile_public';

select 'handle_new_user_signup_v2' as fn, pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'handle_new_user_signup_v2';

-- 2) Triggers sobre tablas relevantes (users, user_profiles, client_profiles)
select n.nspname                           as schema,
       c.relname                           as table,
       t.tgname                            as trigger_name,
       pg_get_triggerdef(t.oid, true)      as trigger_def,
       t.tgenabled                         as enabled
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('users', 'user_profiles', 'client_profiles')
  and not t.tgisinternal
order by c.relname, t.tgname;

-- 3) Esquema de columnas para validar nombres y tipos usados por RPC/triggers
select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name in ('users', 'user_profiles', 'client_profiles')
  and column_name in ('name','phone','address','lat','lon','address_structured','full_name')
order by table_name, column_name;

-- 4) Políticas RLS activas
select schemaname, tablename, polname, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('users','user_profiles','client_profiles')
order by tablename, polname;

-- 5) Grants/privilegios efectivos
select table_name, grantee, privilege_type
from information_schema.table_privileges
where table_schema = 'public'
  and table_name in ('users','user_profiles','client_profiles')
order by table_name, grantee, privilege_type;

-- 6) Estado de datos recientes (sin exponer sensible, útil para diagnóstico rápido)
-- 6a) Conteo de perfiles de cliente con/ sin geolocalización
select
  count(*) filter (where lat is not null and lon is not null) as client_profiles_with_geo,
  count(*) filter (where lat is null or lon is null)          as client_profiles_missing_geo
from public.client_profiles;

-- 6b) Últimos 5 registros en client_profiles
select user_id, address, lat, lon, address_structured, created_at, updated_at
from public.client_profiles
order by created_at desc
limit 5;

-- 6c) Últimos 5 usuarios en public.users
select id, email, role, name, phone, created_at, updated_at
from public.users
order by created_at desc
limit 5;

-- 6d) Últimos 5 perfiles en public.user_profiles
select user_id, full_name, phone, created_at, updated_at
from public.user_profiles
order by created_at desc
limit 5;

-- 7) Dependencias entre RPC y tablas (uso de columnas lat/lon/address_structured)
-- Nota: Busca referencias en el catálogo de dependencias donde sea posible
select distinct
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_depend d on d.objid = p.oid
join pg_class c on c.oid = d.refobjid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('users','user_profiles','client_profiles')
  and p.proname in ('ensure_user_profile_public','handle_new_user_signup_v2')
order by p.proname;

-- Fin del script de auditoría (solo lectura)
