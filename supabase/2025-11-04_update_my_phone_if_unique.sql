-- Secure RPC to update current user's phone only if it's unique
-- Usage: rpc('update_my_phone_if_unique', { p_phone: '+521234567890' })

create or replace function public.update_my_phone_if_unique(
  p_phone text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conflict uuid;
begin
  if p_phone is null or length(trim(p_phone)) = 0 then
    raise exception 'phone_required';
  end if;

  -- Check uniqueness across users excluding current user
  select u.id into v_conflict
  from public.users u
  where u.phone = trim(p_phone)
    and u.id <> auth.uid()
  limit 1;

  if v_conflict is not null then
    raise exception 'phone_in_use';
  end if;

  update public.users
  set phone = trim(p_phone),
      updated_at = now()
  where id = auth.uid();

  if not found then
    raise exception 'profile_not_found';
  end if;
end;
$$;

grant execute on function public.update_my_phone_if_unique(text) to authenticated;
