-- ============================================================================
-- 03_UPDATE_MASTER_HANDLE_SIGNUP.SQL
-- ============================================================================
-- Recreates master_handle_signup trigger ONLY for delivery_agent and restaurant
-- - CLIENT CASE IS NOT MODIFIED (already working correctly)
-- - English roles: delivery_agent, restaurant
-- - No references to OLD.status (fixes error)
-- - Proper handling of vehicle_type, license_plate, restaurant_name, etc.
-- ============================================================================

-- ============================================================================
-- 1. DROP ALL PREVIOUS VERSIONS
-- ============================================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.master_handle_signup() CASCADE;

-- ============================================================================
-- 2. CREATE NEW MASTER_HANDLE_SIGNUP FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION public.master_handle_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_role text;
  v_full_name text;
  v_phone text;
  
  -- Client fields
  v_address text;
  v_lat double precision;
  v_lon double precision;
  v_address_structured jsonb;
  
  -- Delivery agent fields
  v_vehicle_type text;
  v_license_plate text;
  
  -- Restaurant fields
  v_restaurant_name text;
  v_restaurant_address text;
BEGIN
  -- Extract user role (default to 'client' if not specified)
  v_user_role := COALESCE(NEW.raw_user_meta_data->>'user_role', 'client');
  
  -- Extract common fields
  v_full_name := COALESCE(NEW.raw_user_meta_data->>'full_name', '');
  v_phone := COALESCE(NEW.raw_user_meta_data->>'phone', '');
  
  -- ========================================================================
  -- STEP 1: Always create entry in public.users
  -- ========================================================================
  INSERT INTO public.users (
    id,
    email,
    full_name,
    phone,
    user_role,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    NEW.email,
    v_full_name,
    v_phone,
    v_user_role,
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    phone = EXCLUDED.phone,
    user_role = EXCLUDED.user_role,
    updated_at = now();

  -- ========================================================================
  -- STEP 2: Create role-specific profile
  -- ========================================================================
  
  CASE v_user_role
    
    -- ======================================================================
    -- CLIENT PROFILE
    -- ======================================================================
    WHEN 'client' THEN
      -- Extract client-specific fields
      v_address := NEW.raw_user_meta_data->>'address';
      v_lat := (NEW.raw_user_meta_data->>'lat')::double precision;
      v_lon := (NEW.raw_user_meta_data->>'lon')::double precision;
      v_address_structured := COALESCE(
        (NEW.raw_user_meta_data->'address_structured')::jsonb,
        '{}'::jsonb
      );
      
      INSERT INTO public.client_profiles (
        user_id,
        address,
        lat,
        lon,
        address_structured,
        status,
        created_at,
        updated_at
      )
      VALUES (
        NEW.id,
        v_address,
        v_lat,
        v_lon,
        v_address_structured,
        'active',
        now(),
        now()
      )
      ON CONFLICT (user_id) DO UPDATE SET
        address = COALESCE(EXCLUDED.address, client_profiles.address),
        lat = COALESCE(EXCLUDED.lat, client_profiles.lat),
        lon = COALESCE(EXCLUDED.lon, client_profiles.lon),
        address_structured = COALESCE(EXCLUDED.address_structured, client_profiles.address_structured),
        updated_at = now();
      
      RAISE LOG 'Created client_profile for user: % (email: %)', NEW.id, NEW.email;
    
    -- ======================================================================
    -- DELIVERY AGENT PROFILE
    -- ======================================================================
    WHEN 'delivery_agent' THEN
      -- Extract delivery-specific fields
      v_vehicle_type := NEW.raw_user_meta_data->>'vehicle_type';
      v_license_plate := NEW.raw_user_meta_data->>'license_plate';
      
      INSERT INTO public.delivery_agent_profiles (
        user_id,
        vehicle_type,
        vehicle_plate,
        status,
        created_at,
        updated_at
      )
      VALUES (
        NEW.id,
        v_vehicle_type,
        v_license_plate,
        'pending'::delivery_agent_status,
        now(),
        now()
      )
      ON CONFLICT (user_id) DO UPDATE SET
        vehicle_type = COALESCE(EXCLUDED.vehicle_type, delivery_agent_profiles.vehicle_type),
        vehicle_plate = COALESCE(EXCLUDED.vehicle_plate, delivery_agent_profiles.vehicle_plate),
        updated_at = now();
      
      RAISE LOG 'Created delivery_agent_profile for user: % (email: %)', NEW.id, NEW.email;
    
    -- ======================================================================
    -- RESTAURANT PROFILE
    -- ======================================================================
    WHEN 'restaurant' THEN
      -- Extract restaurant-specific fields
      v_restaurant_name := NEW.raw_user_meta_data->>'restaurant_name';
      v_restaurant_address := NEW.raw_user_meta_data->>'restaurant_address';
      v_lat := (NEW.raw_user_meta_data->>'lat')::double precision;
      v_lon := (NEW.raw_user_meta_data->>'lon')::double precision;
      v_address_structured := COALESCE(
        (NEW.raw_user_meta_data->'address_structured')::jsonb,
        '{}'::jsonb
      );
      
      INSERT INTO public.restaurants (
        user_id,
        name,
        address,
        location_lat,
        location_lon,
        address_structured,
        status,
        online,
        created_at,
        updated_at
      )
      VALUES (
        NEW.id,
        v_restaurant_name,
        v_restaurant_address,
        v_lat,
        v_lon,
        v_address_structured,
        'pending',
        false,
        now(),
        now()
      )
      ON CONFLICT (user_id) DO UPDATE SET
        name = COALESCE(EXCLUDED.name, restaurants.name),
        address = COALESCE(EXCLUDED.address, restaurants.address),
        location_lat = COALESCE(EXCLUDED.location_lat, restaurants.location_lat),
        location_lon = COALESCE(EXCLUDED.location_lon, restaurants.location_lon),
        address_structured = COALESCE(EXCLUDED.address_structured, restaurants.address_structured),
        updated_at = now();
      
      RAISE LOG 'Created restaurant for user: % (email: %)', NEW.id, NEW.email;
    
    -- ======================================================================
    -- ADMIN PROFILE (No additional profile needed)
    -- ======================================================================
    WHEN 'admin' THEN
      RAISE LOG 'Admin user created: % (email: %)', NEW.id, NEW.email;
    
    -- ======================================================================
    -- UNKNOWN ROLE (Fallback to client)
    -- ======================================================================
    ELSE
      RAISE WARNING 'Unknown user_role: %. Defaulting to client.', v_user_role;
      
      INSERT INTO public.client_profiles (
        user_id,
        status,
        created_at,
        updated_at
      )
      VALUES (
        NEW.id,
        'active',
        now(),
        now()
      )
      ON CONFLICT (user_id) DO NOTHING;
  END CASE;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Error in master_handle_signup for user %: % (SQLSTATE: %)', 
    NEW.email, SQLERRM, SQLSTATE;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.master_handle_signup IS 
'Master signup trigger that creates user profile based on user_role: client, delivery_agent, restaurant, or admin';

-- ============================================================================
-- 3. CREATE TRIGGER
-- ============================================================================

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.master_handle_signup();

-- ============================================================================
-- 4. VERIFY TRIGGER IS ACTIVE
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

  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ Step 3 Complete: master_handle_signup recreated';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Trigger status: %', CASE WHEN v_trigger_exists THEN '✅ ACTIVE' ELSE '❌ NOT FOUND' END;
  RAISE NOTICE 'Updated roles: delivery_agent, restaurant';
  RAISE NOTICE 'Status field handling: ✅ FIXED (no OLD.status references)';
  RAISE NOTICE '⚠️  CLIENT case NOT MODIFIED (already working)';
  
  IF NOT v_trigger_exists THEN
    RAISE EXCEPTION 'Trigger was not created successfully';
  END IF;
END $$;
