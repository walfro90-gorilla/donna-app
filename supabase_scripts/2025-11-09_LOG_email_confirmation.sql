-- LOG email confirmation trigger end-to-end
-- Purpose: add detailed logs to diagnose failures during email verification

-- 1) Harden function with detailed logging
CREATE OR REPLACE FUNCTION public.handle_user_email_confirmation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Start log
  BEGIN
    INSERT INTO public.debug_user_signup_log(source, event, user_id, email, details)
    VALUES ('email_confirmation', 'START', NEW.id, NEW.email,
            jsonb_build_object(
              'old_email_confirmed_at', OLD.email_confirmed_at,
              'new_email_confirmed_at', NEW.email_confirmed_at,
              'now', now()
            ));
  EXCEPTION WHEN OTHERS THEN
    -- Logging must not break the flow
    NULL;
  END;

  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN
    -- Transition to confirmed: update public.users
    UPDATE public.users 
      SET email_confirm = TRUE,
          updated_at    = now()
    WHERE id = NEW.id;

    BEGIN
      INSERT INTO public.debug_user_signup_log(source, event, user_id, email, details)
      VALUES ('email_confirmation', 'UPDATED_PUBLIC_USERS', NEW.id, NEW.email,
              jsonb_build_object('updated', true));
    EXCEPTION WHEN OTHERS THEN NULL; END;
  ELSE
    -- No relevant change, skip
    BEGIN
      INSERT INTO public.debug_user_signup_log(source, event, user_id, email, details)
      VALUES ('email_confirmation', 'SKIP_NO_CHANGE', NEW.id, NEW.email,
              jsonb_build_object('reason', 'no_transition'));
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log the failure and rethrow to surface upstream (so Supabase returns error)
  BEGIN
    INSERT INTO public.debug_user_signup_log(source, event, user_id, email, details)
    VALUES ('email_confirmation', 'ERROR', NEW.id, NEW.email,
            jsonb_build_object('error', SQLERRM, 'state', SQLSTATE));
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RAISE;
END;
$$;

-- 2) Ensure trigger exists and fires only when email_confirmed_at changes
DROP TRIGGER IF EXISTS on_auth_user_email_confirmed ON auth.users;
CREATE TRIGGER on_auth_user_email_confirmed
  AFTER UPDATE OF email_confirmed_at ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_user_email_confirmation();

-- 3) Allow reading logs for debugging from the app (optional)
GRANT SELECT ON TABLE public.debug_user_signup_log TO authenticated;

-- 4) Quick checks (optional to run manually):
-- SELECT id, email, email_confirm FROM public.users ORDER BY created_at DESC LIMIT 5;
-- SELECT id, email, email_confirmed_at FROM auth.users ORDER BY created_at DESC LIMIT 5;
-- SELECT * FROM public.debug_user_signup_log WHERE source='email_confirmation' ORDER BY created_at DESC LIMIT 50;
