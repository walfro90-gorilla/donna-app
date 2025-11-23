-- ===================================================================
-- DIAGNÓSTICO V2: Pila de signup en Supabase
-- Objetivo: identificar la causa exacta del 500 en /auth/v1/signup
-- Ejecuta todo este script en el SQL Editor y comparte TODOS los resultados.
-- No modifica datos (usa solo SELECT y tests en transacción con ROLLBACK).
-- ===================================================================

-- 1) Versión rápida del esquema de client_profiles (confirmación)
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='client_profiles'
order by ordinal_position;

-- 2) Triggers activos sobre auth.users
select
  t.tgname as trigger_name,
  n.nspname as trigger_schema,
  c.relname as table_name,
  pg_get_triggerdef(t.oid, true) as trigger_def,
  p.proname as function_name,
  np.nspname as function_schema,
  p.oid as function_oid
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
left join pg_proc p on p.oid = t.tgfoid
left join pg_namespace np on np.oid = p.pronamespace
where c.relname = 'users' and n.nspname = 'auth' and t.tgenabled <> 'D';

-- 3) Código fuente de las funciones de los triggers anteriores
-- Nota: copia los OIDs function_oid del resultado anterior
-- y pégalos en la lista para ver el código exacto.
-- Si no conoces los OIDs aún, ejecuta primero la sección 2 y luego esta.
-- Reemplaza {OID1},{OID2} si hay más de una.
-- (Si no sabes cuáles son, vuelve a ejecutar después de ver la sección 2.)
-- select pg_get_functiondef({OID1});
-- select pg_get_functiondef({OID2});

-- 4) Buscamos funciones candidatas en esquema public relacionadas a perfiles
select p.oid as func_oid, n.nspname as schema, p.proname as name,
       p.prosecdef as security_definer,
       pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public'
  and (p.proname ilike '%profile%' or p.proname ilike '%ensure%' or p.proname ilike '%account%')
order by p.proname;

-- 5) Políticas RLS relevantes sobre public.client_profiles y public.users
select *
from pg_policies
where schemaname='public' and tablename in ('client_profiles','users')
order by tablename, polname;

-- 6) ¿RLS habilitado en tablas clave?
select schemaname, tablename, rowsecurity
from pg_tables
where schemaname='public' and tablename in ('client_profiles','users')
order by tablename;

-- 7) Owner de tablas (para saber si bypass de RLS aplica por owner)
select table_schema, table_name, tableowner
from information_schema.tables
where table_schema='public' and table_name in ('client_profiles','users')
order by table_name;

-- 8) Simulación controlada: probamos la función principal con role=authenticator
-- IMPORTANTE:
--  - Esto reproduce el contexto más parecido al real de GoTrue.
--  - No hará persistencia (se hace ROLLBACK al final).

do $$ begin end $$; -- no-op (mantiene editor content)

begin;
  -- Genera un UUID aleatorio para simular new user id
  select gen_random_uuid() as simulated_user_id \gset

  -- Tomamos nota del rol actual
  select current_user as current_user_before;

  -- Intentamos ejecutar como role authenticator
  -- (si falla, anota el error exacto)
  set local role authenticator;

  -- Si existe la función ensure_client_profile_and_account, probamos
  do $$
  declare
    _exists bool;
  begin
    select exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname='public' and p.proname='ensure_client_profile_and_account'
    ) into _exists;

    if _exists then
      perform public.ensure_client_profile_and_account(:'simulated_user_id');
    end if;
  end $$;

rollback;

-- 9) Mensaje esperado:
--  - Si aquí obtienes "violates row-level security policy" => PROBLEMA DE RLS
--  - Si obtienes error de columna inexistente o constraint => PROBLEMA DE FUNCIÓN/ESQUEMA
--  - Si no hay error => la ruta real del trigger posiblemente usa otra función.

-- 10) Por último, listamos dependencias del trigger hacia funciones externas
select distinct p.proname as called_function,
       n.nspname as schema,
       p.oid,
       pg_get_functiondef(p.oid)
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n1 on n1.oid = c.relnamespace
join pg_proc tf on tf.oid = t.tgfoid -- trigger function
join pg_namespace nf on nf.oid = tf.pronamespace
join pg_depend d on d.objid = tf.oid
join pg_proc p on p.oid = d.refobjid -- funciones referenciadas
join pg_namespace n on n.oid = p.pronamespace
where n1.nspname='auth' and c.relname='users';

-- ===================================================================
-- FIN DIAGNÓSTICO V2
-- Comparte los resultados completos (secciones 2, 3, 4, 5, 6, 8 y 10).
-- ===================================================================
