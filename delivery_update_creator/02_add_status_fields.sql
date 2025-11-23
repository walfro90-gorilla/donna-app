-- ============================================================================
-- 02_ADD_STATUS_FIELDS.SQL
-- ============================================================================
-- ⚠️  THIS SCRIPT IS NOT NEEDED - STATUS FIELDS ALREADY EXIST
-- ============================================================================
-- 
-- According to your DATABASE_SCHEMA.sql:
-- - delivery_agent_profiles.status ALREADY EXISTS (type: delivery_agent_status enum)
-- - restaurants.status ALREADY EXISTS (type: text with CHECK constraint)
-- 
-- This script is kept for documentation purposes only.
-- It will verify that status fields exist and skip if they do.
-- 
-- ============================================================================

-- ============================================================================
-- VERIFY STATUS FIELDS EXIST (NO MODIFICATIONS)
-- ============================================================================

DO $$
DECLARE
  v_delivery_status boolean;
  v_restaurant_status boolean;
BEGIN
  -- Check delivery_agent_profiles.status
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'delivery_agent_profiles' 
    AND column_name = 'status'
  ) INTO v_delivery_status;

  -- Check restaurants.status
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'restaurants' 
    AND column_name = 'status'
  ) INTO v_restaurant_status;

  -- Report results
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ Step 2 Complete: Status fields verified';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'delivery_agent_profiles.status: %', CASE WHEN v_delivery_status THEN '✅ EXISTS (no changes needed)' ELSE '❌ MISSING' END;
  RAISE NOTICE 'restaurants.status: %', CASE WHEN v_restaurant_status THEN '✅ EXISTS (no changes needed)' ELSE '❌ MISSING' END;
  RAISE NOTICE '⚠️  client_profiles NOT MODIFIED (already working)';
  
  IF NOT (v_delivery_status AND v_restaurant_status) THEN
    RAISE EXCEPTION 'Some status columns are missing. This is unexpected. Check your database schema.';
  END IF;
  
  RAISE NOTICE '';
  RAISE NOTICE '✅ All status fields exist. No modifications needed.';
  RAISE NOTICE 'Proceed to script 03_update_master_handle_signup.sql';
END $$;
