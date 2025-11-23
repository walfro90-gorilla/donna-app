-- RPCs para soporte de liquidaciones manuales y filtrado de restaurantes con deuda

-- 1) Listado de cuentas (admin)
create or replace function public.rpc_admin_list_accounts(p_account_type text default null)
returns setof public.accounts
language sql
security definer
set search_path = public, extensions
as $$
  select *
  from public.accounts a
  where p_account_type is null or lower(a.account_type) = lower(p_account_type)
  order by a.created_at desc;
$$;

-- 2) Crear liquidación manual (admin)
-- Inserta una fila en settlements y opcionalmente la marca como completada para disparar los triggers existentes
create or replace function public.rpc_admin_create_settlement(
  p_payer_account_id uuid,
  p_receiver_account_id uuid,
  p_amount numeric,
  p_notes text default null,
  p_auto_complete boolean default true
) returns public.settlements
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_row public.settlements;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'Monto inválido';
  end if;
  if p_payer_account_id = p_receiver_account_id then
    raise exception 'Pagador y receptor no pueden ser la misma cuenta';
  end if;

  insert into public.settlements (payer_account_id, receiver_account_id, amount, status, notes, initiated_at)
  values (p_payer_account_id, p_receiver_account_id, p_amount, 'pending', p_notes, now())
  returning * into v_row;

  if p_auto_complete then
    update public.settlements
      set status = 'completed',
          completed_by = auth.uid(),
          completed_at = now()
    where id = v_row.id
    returning * into v_row;
  end if;

  return v_row;
end;
$$;

-- 3) Listar restaurantes con deuda para un repartidor (dropdown filtrado)
-- Heurística: suma de pedidos pagados en efectivo entregados por el repartidor al restaurante
--   menos las liquidaciones completadas de ese repartidor hacia ese restaurante.
create or replace function public.rpc_list_restaurants_with_debt_for_delivery(
  p_delivery_account_id uuid
) returns table (
  restaurant_user_id uuid,
  account_id uuid,
  name text,
  amount_due numeric
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_delivery_user_id uuid;
begin
  -- Resolver el user_id del repartidor a partir de su account_id
  select a.user_id into v_delivery_user_id
  from public.accounts a
  where a.id = p_delivery_account_id;

  if v_delivery_user_id is null then
    return;
  end if;

  return query
  with r as (
    select r.user_id as restaurant_user_id,
           r.name as name,
           -- cuenta del restaurante (si existe)
           (select a.id from public.accounts a 
             where a.user_id = r.user_id and lower(a.account_type) like 'restaur%'
             order by a.created_at asc limit 1) as account_id
    from public.restaurants r
  ),
  cash_orders as (
    select o.restaurant_id,
           sum(coalesce(o.total_amount, 0))::numeric as total_cash
    from public.orders o
    where o.delivery_agent_id = v_delivery_user_id
      and (o.status = 'delivered')
      and (o.payment_method = 'cash')
    group by o.restaurant_id
  ),
  settled as (
    select ar.user_id as restaurant_user_id,
           sum(coalesce(s.amount, 0))::numeric as total_settled
    from public.settlements s
    join public.accounts ad on ad.id = s.payer_account_id   -- cuenta del repartidor
    join public.accounts ar on ar.id = s.receiver_account_id -- cuenta del restaurante
    where ad.user_id = v_delivery_user_id
      and lower(ar.account_type) like 'restaur%'
      and s.status = 'completed'
    group by ar.user_id
  )
  select r.restaurant_user_id,
         r.account_id,
         r.name,
         greatest(coalesce(co.total_cash, 0) - coalesce(st.total_settled, 0), 0) as amount_due
  from r
  left join public.restaurants rr on rr.user_id = r.restaurant_user_id
  left join cash_orders co on co.restaurant_id = rr.id
  left join settled st on st.restaurant_user_id = r.restaurant_user_id
  where greatest(coalesce(co.total_cash, 0) - coalesce(st.total_settled, 0), 0) > 0
  order by amount_due desc, r.name asc;
end;
$$;
