-- =====================================================
-- Script 85: Add view and helper function to get email verification status
-- Purpose: Join auth.users with public.users to expose email_confirmed_at
-- =====================================================

-- 1. Create a secure function that returns email_confirmed_at for a given user_id
-- This bypasses RLS and reads directly from auth.users
CREATE OR REPLACE FUNCTION public.get_email_confirmed_at(p_user_id UUID)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_confirmed_at TIMESTAMPTZ;
BEGIN
  SELECT email_confirmed_at
  INTO v_confirmed_at
  FROM auth.users
  WHERE id = p_user_id;
  
  RETURN v_confirmed_at;
END;
$$;

-- 2. Add comment explaining the function
COMMENT ON FUNCTION public.get_email_confirmed_at(UUID) IS 
'Returns the email_confirmed_at timestamp from auth.users for a given user_id. Used to check email verification status.';

-- 3. Grant execute permission to authenticated users and service role
GRANT EXECUTE ON FUNCTION public.get_email_confirmed_at(UUID) TO authenticated, anon, service_role;

-- =====================================================
-- Usage example:
-- SELECT id, email, public.get_email_confirmed_at(id) as email_confirmed_at FROM public.users;
-- =====================================================
