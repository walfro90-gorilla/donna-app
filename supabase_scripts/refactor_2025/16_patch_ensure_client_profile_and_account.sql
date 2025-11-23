-- ===================================================================
-- FIX OPCIONAL 2: Re-crear ensure_client_profile_and_account con SECURITY DEFINER + logs
-- Úsalo si el diagnóstico muestra que la ruta de signup llama a esta función
-- y falla por RLS o por campos.
-- ===================================================================

-- 0) Infra de logging mínima (idempotente)
create table if not exists public.app_db_log (
  id bigserial primary key,
  ts timestamptz not null default now(),
  level text not null check (level in ('debug','info','warn','error')),
  source text not null,
  message text,
  details jsonb
);

create or replace function public.log_db(p_level text, p_source text, p_message text, p_details jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.app_db_log(level, source, message, details)
  values (p_level, p_source, p_message, p_details);
exception when others then
  -- evitar fallar por logging
  null;
end; $$;

-- 1) Función ensure_client_profile_and_account (idempotente)
create or replace function public.ensure_client_profile_and_account(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _exists boolean;
begin
  perform public.log_db('debug','ensure_client_profile_and_account','start', jsonb_build_object('user_id', p_user_id));

  -- Upsert tabla public.users (si tu app mantiene espejo de auth.users)
  if to_regclass('public.users') is not null then
    insert into public.users (id)
    values (p_user_id)
    on conflict (id) do nothing;
  end if;

  -- Upsert client_profiles con status por defecto activo
  select exists(select 1 from public.client_profiles where user_id = p_user_id) into _exists;
  if not _exists then
    insert into public.client_profiles(user_id, status)
    values (p_user_id, 'active');
  else
    update public.client_profiles set updated_at = now() where user_id = p_user_id;
  end if;

  perform public.log_db('info','ensure_client_profile_and_account','ok', jsonb_build_object('user_id', p_user_id));
exception when others then
  perform public.log_db('error','ensure_client_profile_and_account','exception', jsonb_build_object('user_id', p_user_id, 'sqlerrm', sqlerrm, 'sqlstate', sqlstate));
  raise;
end; $$;

grant execute on function public.ensure_client_profile_and_account(uuid) to authenticated, anon, service_role, postgres, supabase_admin, supabase_auth_admin, authenticator;

-- ===================================================================
-- FIN FIX OPCIONAL 2
-- ===================================================================
