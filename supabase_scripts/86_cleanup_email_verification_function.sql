-- =====================================================
-- Script 86: Cleanup obsolete email verification function
-- Purpose: Remove the get_email_confirmed_at function that is no longer needed
-- Reason: We now use the email_confirm boolean field directly from public.users
-- =====================================================

-- Drop the function if it exists (it's no longer needed)
DROP FUNCTION IF EXISTS public.get_email_confirmed_at(UUID);

-- Add a comment explaining that we use email_confirm instead
COMMENT ON COLUMN public.users.email_confirm IS 
'Boolean flag indicating if user has verified their email. Synced from auth.users.email_confirmed_at via trigger.';

-- =====================================================
-- Note: The app now uses public.users.email_confirm (boolean) directly
-- instead of calling a function to get auth.users.email_confirmed_at (timestamp)
-- =====================================================
