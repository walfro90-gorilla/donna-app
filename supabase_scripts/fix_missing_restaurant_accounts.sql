-- ============================================================
-- Fix: Crear cuentas faltantes para restaurantes existentes
-- ============================================================

-- Insertar cuentas para restaurantes que no tienen cuenta en accounts
insert into public.accounts (user_id, account_type, balance)
select 
  r.user_id,
  'restaurant' as account_type,
  0.00 as balance
from public.restaurants r
left join public.accounts a on (a.user_id = r.user_id and a.account_type = 'restaurant')
where a.id is null;

-- Verificar que todos los restaurantes ahora tienen cuenta
select 
  r.id as restaurant_id,
  r.name as restaurant_name,
  r.user_id,
  a.id as account_id,
  a.balance
from public.restaurants r
left join public.accounts a on (a.user_id = r.user_id and a.account_type = 'restaurant')
order by r.name;