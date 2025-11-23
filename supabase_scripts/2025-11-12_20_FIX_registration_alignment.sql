-- 2025-11-12_20_FIX_registration_alignment.sql
-- Purpose: Align registration RPCs and triggers strictly with DATABASE_SCHEMA.sql
-- - public.users no longer contains address/lat/lon/address_structured
-- - Address and geolocation live in public.client_profiles
-- - Ensure atomic creation path: auth.users -> public.users -> client_profiles (+account)
-- Safe, idempotent, SECURITY DEFINER functions. Avoids changing existing return types of other functions.

set search_path = public;

-- 0) Clean up conflicting function overloads for ensure_user_profile_public to avoid 42P13
do $$
begin
  for select p.oid
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'ensure_user_profile_public'
  loop
    execute 'drop function if exists public.ensure_user_profile_public('||pg_get_function_identity_arguments(oid)||') cascade';
  end loop;
exception when others then
  raise notice 'Cleanup notice (ensure_user_profile_public): %', sqlerrm;
end $$;

-- 1) Ensure minimal upsert into public.users and delegate address to client_profiles
create or replace function public.ensure_user_profile_public(
  p_user_id uuid,
  p_email text,
  p_name text default '',
  p_role text default 'client',
  p_phone text default '',
  -- legacy-compatible params (ignored by users table, used to update client_profiles)
  p_address text default null,
  p_lat double precision default null,
  p_lon double precision default null,
  p_address_structured jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_is_email_confirmed boolean := false;
  v_exists boolean;
begin
  if p_user_id is null then
    raise exception 'p_user_id is required';
  end if;

  -- Validate auth.users presence
  perform 1 from auth.users where id = p_user_id;
  if not found then
    raise exception 'User ID % does not exist in auth.users', p_user_id;
  end if;

  -- Derive email confirmation from auth
  select (email_confirmed_at is not null)
    into v_is_email_confirmed
  from auth.users where id = p_user_id;

  -- Upsert minimal profile strictly to columns present in DATABASE_SCHEMA.sql
  select exists(select 1 from public.users where id = p_user_id) into v_exists;
  if not v_exists then
    insert into public.users (
      id, email, name, phone, role, email_confirm, created_at, updated_at
    ) values (
      p_user_id,
      coalesce(p_email, ''),
      coalesce(p_name, ''),
      coalesce(p_phone, ''),
      coalesce(p_role, 'client'),
      coalesce(v_is_email_confirmed, false),
      v_now,
      v_now
    );
  else
    update public.users set
      email = coalesce(nullif(p_email, ''), email),
      name = coalesce(nullif(p_name, ''), name),
      phone = coalesce(nullif(p_phone, ''), phone),
      -- only normalize role if current role is empty/client/cliente
      role = case when coalesce(role, '') in ('', 'client', 'cliente') then coalesce(p_role, 'client') else role end,
      email_confirm = coalesce(email_confirm, v_is_email_confirmed),
      updated_at = v_now
    where id = p_user_id;
  end if;

  -- Ensure client profile + financial account exists (idempotent)
  perform public.ensure_client_profile_and_account(p_user_id);

  -- If address provided, update client_profiles via dedicated RPC (idempotent)
  if coalesce(p_address, '') <> '' or p_lat is not null or p_lon is not null or p_address_structured is not null then
    begin
      perform public.update_client_default_address(
        p_user_id => p_user_id,
        p_address => coalesce(p_address, ''),
        p_lat => p_lat,
        p_lon => p_lon,
        p_address_structured => p_address_structured
      );
    exception when others then
      -- non-fatal; address can be provided later from app
      raise notice 'update_client_default_address failed (non-fatal): %', sqlerrm;
    end;
  end if;

  return jsonb_build_object('success', true, 'data', jsonb_build_object('user_id', p_user_id), 'error', null);
exception when others then
  return jsonb_build_object('success', false, 'data', null, 'error', sqlerrm);
end;
$$;

grant execute on function public.ensure_user_profile_public(uuid, text, text, text, text, text, double precision, double precision, jsonb)
  to anon, authenticated, service_role;

-- 2) Keep create_user_profile_public as a thin wrapper to the ensure function to avoid schema drift
do $$
begin
  -- Drop mismatched create_user_profile_public to avoid overload conflicts
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'create_user_profile_public'
  ) then
    execute 'drop function public.create_user_profile_public cascade';
  end if;
exception when others then
  raise notice 'Cleanup notice (create_user_profile_public): %', sqlerrm;
end $$;

create or replace function public.create_user_profile_public(
  p_user_id uuid,
  p_email text,
  p_name text,
  p_phone text,
  p_address text,
  p_role text,
  p_lat double precision default null,
  p_lon double precision default null,
  p_address_structured jsonb default null,
  p_is_temp_password boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.ensure_user_profile_public(
    p_user_id => p_user_id,
    p_email => p_email,
    p_name => p_name,
    p_role => p_role,
    p_phone => p_phone,
    p_address => p_address,
    p_lat => p_lat,
    p_lon => p_lon,
    p_address_structured => p_address_structured
  );
end;
$$;

grant execute on function public.create_user_profile_public(uuid, text, text, text, text, text, double precision, double precision, jsonb, boolean)
  to anon, authenticated, service_role;

-- 3) Ensure triggers exist to auto-create profiles/accounts on inserts
-- 3.a) public.users AFTER INSERT -> ensure_client_profile_and_account
create or replace function public._trg_call_ensure_client_profile_and_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.ensure_client_profile_and_account(new.id);
  return new;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_client_profile_on_user_insert') then
    create trigger trg_client_profile_on_user_insert
    after insert on public.users
    for each row
    when (new.role in ('client','cliente'))
    execute function public._trg_call_ensure_client_profile_and_account();
  end if;
end $$;

-- 3.b) Optional: auth.users AFTER INSERT -> ensure_user_profile_public
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.ensure_user_profile_public(
    p_user_id => new.id,
    p_email => coalesce(new.email, ''),
    p_name => coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''),
    p_role => 'client'
  );
  return new;
end;
$$;

do $$
begin
  begin
    if not exists (select 1 from pg_trigger where tgname = 'trg_handle_new_user_on_auth_users') then
      execute 'create trigger trg_handle_new_user_on_auth_users
               after insert on auth.users
               for each row execute function public.handle_new_user()';
    end if;
  exception when others then
    -- Not critical if auth schema is locked down
    raise notice 'Could not create trigger on auth.users (non-critical): %', sqlerrm;
  end;
end $$;

-- 4) Quick verification helpers (optional)
-- select p.proname, pg_get_function_identity_arguments(p.oid) args
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname='public' and p.proname in (
--   'ensure_user_profile_public','create_user_profile_public','ensure_client_profile_and_account','update_client_default_address'
-- ) order by 1;
