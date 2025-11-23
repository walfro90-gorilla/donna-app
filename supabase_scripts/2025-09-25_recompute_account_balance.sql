-- Security-definer RPC to recompute and persist the balance of an account
-- Safe to run in Supabase SQL editor.
-- Usage: select public.rpc_recompute_account_balance(p_account_id => '<uuid>');

create or replace function public.rpc_recompute_account_balance(p_account_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Recompute the sum of all transactions for the account
  update public.accounts a
  set balance = coalesce((
    select sum(at.amount)::numeric
    from public.account_transactions at
    where at.account_id = p_account_id
  ), 0),
  updated_at = now()
  where a.id = p_account_id;
end;
$$;

revoke all on function public.rpc_recompute_account_balance(uuid) from public;
-- Grant execution to authenticated users; adjust as needed
grant execute on function public.rpc_recompute_account_balance(uuid) to authenticated, service_role;
