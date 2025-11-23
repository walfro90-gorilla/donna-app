-- Recompute a single account balance from account_transactions
-- Idempotent: safe to run multiple times
-- Requires: public.accounts(id, balance numeric), public.account_transactions(account_id uuid, amount numeric)

CREATE OR REPLACE FUNCTION public.fn_accounts_recompute_balance(p_account_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_sum numeric;
BEGIN
  -- Ensure search_path to avoid SECURITY DEFINER hijack
  PERFORM set_config('search_path', 'public', true);

  SELECT COALESCE(SUM(at.amount), 0)
    INTO v_sum
  FROM public.account_transactions at
  WHERE at.account_id = p_account_id;

  -- Lock the account row to avoid write skew under concurrency
  PERFORM 1 FROM public.accounts a WHERE a.id = p_account_id FOR UPDATE;

  UPDATE public.accounts a
     SET balance = v_sum
   WHERE a.id = p_account_id;
END;
$$;

COMMENT ON FUNCTION public.fn_accounts_recompute_balance(uuid)
  IS 'Recomputes accounts.balance from the sum of account_transactions.amount for the given account_id';
