-- ============================================================================
-- 04_VERIFY_SETUP.SQL
-- ============================================================================
-- Verification script to ensure all components are properly configured
-- ============================================================================

-- ============================================================================
-- 1. VERIFY REGISTRATION RPCS EXIST
-- ============================================================================

DO $$
DECLARE
  v_count int;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public'
  AND p.proname IN (
    'register_delivery_agent_v2',
    'register_restaurant_v2'
  );

  RAISE NOTICE '========================================';
  RAISE NOTICE '1. REGISTRATION RPCs';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Found % registration functions (expected: 2)', v_count;
  
  IF v_count = 2 THEN
    RAISE NOTICE '✅ register_delivery_agent_v2';
    RAISE NOTICE '✅ register_restaurant_v2';
    RAISE NOTICE '⚠️  register_client NOT CHECKED (already working)';
  ELSE
    RAISE WARNING '❌ Some registration functions are missing!';
  END IF;
END $$;

-- ============================================================================
-- 2. VERIFY MASTER_HANDLE_SIGNUP EXISTS
-- ============================================================================

DO $$
DECLARE
  v_count int;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public'
  AND p.proname = 'master_handle_signup';

  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '2. SIGNUP TRIGGER FUNCTION';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Found % master_handle_signup functions (expected: 1)', v_count;
  
  IF v_count = 1 THEN
    RAISE NOTICE '✅ master_handle_signup (single version)';
  ELSIF v_count = 0 THEN
    RAISE WARNING '❌ master_handle_signup NOT FOUND!';
  ELSE
    RAISE WARNING '⚠️  Multiple versions of master_handle_signup found (%)!', v_count;
  END IF;
END $$;

-- ============================================================================
-- 3. VERIFY TRIGGER IS ATTACHED
-- ============================================================================

DO $$
DECLARE
  v_trigger_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'auth'
    AND c.relname = 'users'
    AND t.tgname = 'on_auth_user_created'
  ) INTO v_trigger_exists;

  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '3. TRIGGER ATTACHMENT';
  RAISE NOTICE '========================================';
  
  IF v_trigger_exists THEN
    RAISE NOTICE '✅ Trigger "on_auth_user_created" is active on auth.users';
  ELSE
    RAISE WARNING '❌ Trigger "on_auth_user_created" NOT FOUND on auth.users!';
  END IF;
END $$;

-- ============================================================================
-- 4. VERIFY STATUS COLUMNS
-- ============================================================================

DO $$
DECLARE
  v_delivery_status boolean;
  v_restaurant_status boolean;
BEGIN
  -- Check delivery_agent_profiles
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'delivery_agent_profiles' 
    AND column_name = 'status'
  ) INTO v_delivery_status;

  -- Check restaurants
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'restaurants' 
    AND column_name = 'status'
  ) INTO v_restaurant_status;

  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '4. STATUS COLUMNS';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'delivery_agent_profiles.status: %', CASE WHEN v_delivery_status THEN '✅' ELSE '❌' END;
  RAISE NOTICE 'restaurants.status: %', CASE WHEN v_restaurant_status THEN '✅' ELSE '❌' END;
  RAISE NOTICE '⚠️  client_profiles NOT CHECKED (already working)';
END $$;

-- ============================================================================
-- 5. VERIFY DELIVERY FIELDS
-- ============================================================================

DO $$
DECLARE
  v_vehicle_type boolean;
  v_license_plate boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'delivery_agent_profiles' 
    AND column_name = 'vehicle_type'
  ) INTO v_vehicle_type;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'delivery_agent_profiles' 
    AND column_name = 'vehicle_plate'
  ) INTO v_license_plate;

  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '5. DELIVERY AGENT FIELDS';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'delivery_agent_profiles.vehicle_type: %', CASE WHEN v_vehicle_type THEN '✅' ELSE '❌' END;
  RAISE NOTICE 'delivery_agent_profiles.vehicle_plate: %', CASE WHEN v_license_plate THEN '✅' ELSE '❌' END;
END $$;

-- ============================================================================
-- 6. VERIFY RESTAURANT FIELDS
-- ============================================================================

DO $$
DECLARE
  v_restaurant_name boolean;
  v_restaurant_address boolean;
  v_lat boolean;
  v_lon boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'restaurants' 
    AND column_name = 'name'
  ) INTO v_restaurant_name;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'restaurants' 
    AND column_name = 'address'
  ) INTO v_restaurant_address;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'restaurants' 
    AND column_name = 'location_lat'
  ) INTO v_lat;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'restaurants' 
    AND column_name = 'location_lon'
  ) INTO v_lon;

  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '6. RESTAURANT FIELDS';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'restaurants.name: %', CASE WHEN v_restaurant_name THEN '✅' ELSE '❌' END;
  RAISE NOTICE 'restaurants.address: %', CASE WHEN v_restaurant_address THEN '✅' ELSE '❌' END;
  RAISE NOTICE 'restaurants.location_lat: %', CASE WHEN v_lat THEN '✅' ELSE '❌' END;
  RAISE NOTICE 'restaurants.location_lon: %', CASE WHEN v_lon THEN '✅' ELSE '❌' END;
END $$;

-- ============================================================================
-- 7. FINAL SUMMARY
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ VERIFICATION COMPLETE';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Review all sections above.';
  RAISE NOTICE 'All items should show ✅ for successful setup.';
  RAISE NOTICE '';
  RAISE NOTICE '⚠️  CLIENT registration NOT MODIFIED (already working)';
  RAISE NOTICE '';
  RAISE NOTICE 'If any ❌ or ⚠️  appear, re-run the corresponding script:';
  RAISE NOTICE '  - Missing RPCs → 01_create_registration_rpcs.sql';
  RAISE NOTICE '  - Missing status → 02_add_status_fields.sql';
  RAISE NOTICE '  - Missing trigger → 03_update_master_handle_signup.sql';
  RAISE NOTICE '';
  RAISE NOTICE 'Next step: Update Flutter frontend files for delivery_agent and restaurant only';
END $$;
