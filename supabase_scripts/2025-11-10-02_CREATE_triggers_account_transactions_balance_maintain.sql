-- Maintain accounts.balance on changes to account_transactions
-- Creates trigger function and trigger. Safe to re-run.

-- Drop old trigger if present
DROP TRIGGER IF EXISTS trg_account_transactions_balance_maintain ON public.account_transactions;

-- Create trigger function handling INSERT/UPDATE/DELETE deltas by recomputation
CREATE OR REPLACE FUNCTION public.fn_on_account_transactions_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM set_config('search_path', 'public', true);

  IF TG_OP = 'INSERT' THEN
    PERFORM public.fn_accounts_recompute_balance(NEW.account_id);
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    -- If account_id changed, recompute both accounts
    IF NEW.account_id IS DISTINCT FROM OLD.account_id THEN
      PERFORM public.fn_accounts_recompute_balance(OLD.account_id);
      PERFORM public.fn_accounts_recompute_balance(NEW.account_id);
    ELSE
      -- Amount or other fields changed; recompute target account
      PERFORM public.fn_accounts_recompute_balance(NEW.account_id);
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    PERFORM public.fn_accounts_recompute_balance(OLD.account_id);
    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;

-- Create trigger after row change to ensure final values are visible
CREATE TRIGGER trg_account_transactions_balance_maintain
AFTER INSERT OR UPDATE OR DELETE ON public.account_transactions
FOR EACH ROW
EXECUTE FUNCTION public.fn_on_account_transactions_change();

COMMENT ON TRIGGER trg_account_transactions_balance_maintain ON public.account_transactions
  IS 'Keeps accounts.balance in sync with account_transactions by recomputing on row changes';

-- Helpful index (no-op if it already exists)
CREATE INDEX IF NOT EXISTS idx_account_transactions_account_id
  ON public.account_transactions(account_id);
