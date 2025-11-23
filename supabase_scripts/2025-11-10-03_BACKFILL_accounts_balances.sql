-- Backfill all accounts.balance from account_transactions
-- Run once after deploying the trigger/functions or whenever you need to resync

-- Fast correlated update for all accounts
UPDATE public.accounts a
   SET balance = COALESCE((
        SELECT SUM(at.amount)
          FROM public.account_transactions at
         WHERE at.account_id = a.id
     ), 0);

-- Optionally, force recompute via function for sanity
DO $$
DECLARE r record;
BEGIN
  PERFORM set_config('search_path', 'public', true);
  FOR r IN SELECT id FROM public.accounts LOOP
    PERFORM public.fn_accounts_recompute_balance(r.id);
  END LOOP;
END $$;
