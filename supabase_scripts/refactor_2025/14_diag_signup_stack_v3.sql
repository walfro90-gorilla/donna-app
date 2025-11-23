-- 14_diag_signup_stack_v3.sql
-- Compatible con Supabase SQL Editor / migraciones (sin comandos psql como \gset, \echo, etc.)
-- Objetivo: identificar el trigger y la(s) función(es) que se ejecutan en signup (auth.users)
-- y revisar políticas/definiciones que puedan causar el error 500 "Database error saving new user".

-- 1) Contexto básico
select current_user, session_user, version();

-- 2) Triggers en auth.users (no internos)
with trg as (
  select 
    t.oid                             as trigger_oid,
    t.tgname                          as trigger_name,
    case t.tgenabled when 'O' then 'ENABLED' when 'D' then 'DISABLED' else t.tgenabled end as enabled,
    p.oid                             as function_oid,
    nsp.nspname                       as function_schema,
    p.proname                         as function_name
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace ns on ns.oid = c.relnamespace
  join pg_proc p on p.oid = t.tgfoid
  join pg_namespace nsp on nsp.oid = p.pronamespace
  where ns.nspname = 'auth'
    and c.relname = 'users'
    and not t.tgisinternal
)
select * from trg order by trigger_name;

-- 3) Definición de las funciones de esos triggers
select 
  n.nspname              as schema,
  p.proname              as name,
  pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where p.oid in (
  select p.oid
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace ns on ns.oid = c.relnamespace
  join pg_proc p on p.oid = t.tgfoid
  where ns.nspname = 'auth'
    and c.relname = 'users'
    and not t.tgisinternal
);

-- 4) Políticas RLS en public.users y public.client_profiles
select polname, schemaname, tablename, cmd, qual, with_check from (
  select 
    pol.polname,
    n.nspname as schemaname,
    c.relname as tablename,
    case pol.polcmd 
      when 'r' then 'SELECT' 
      when 'a' then 'INSERT' 
      when 'w' then 'UPDATE' 
      when 'd' then 'DELETE' 
      else pol.polcmd 
    end as cmd,
    pg_get_expr(pol.polqual, pol.polrelid)       as qual,
    pg_get_expr(pol.polwithcheck, pol.polrelid)  as with_check
  from pg_policy pol
  join pg_class c on c.oid = pol.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname in ('users','client_profiles')
)
as rls
order by schemaname, tablename, polname;

-- 5) Columnas en public.users y public.client_profiles
select 
  table_name, 
  column_name, 
  data_type, 
  is_nullable, 
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in ('users','client_profiles')
order by table_name, ordinal_position;

-- 6) Funciones en esquema public que referencian client_profiles (para localizar ensure_* o similares)
select 
  n.nspname as schema,
  p.proname as function_name,
  pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (
    lower(p.proname) like '%client%'
    or lower(p.proname) like '%profile%'
    or lower(p.proname) like '%user%'
  )
  and pg_get_functiondef(p.oid) ilike '%client_profiles%'
order by p.proname;

-- 7) Grants sobre public.users y public.client_profiles para roles relevantes (incl. authenticator)
select
  n.nspname as schema,
  c.relname as table_name,
  tp.grantee,
  tp.privilege_type
from information_schema.table_privileges tp
join pg_class c on c.relname = tp.table_name
join pg_namespace n on n.nspname = tp.table_schema
where tp.table_schema = 'public'
  and tp.table_name in ('users','client_profiles')
order by table_name, privilege_type, grantee;

-- Fin del diagnóstico v3
