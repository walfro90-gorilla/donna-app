-- =============================================
-- Script 4: Seed Test Data (FIXED)
-- =============================================
-- This script creates test data for the application
-- It properly handles the auth.users foreign key constraint

DO $$
DECLARE
  v_test_user_id uuid;
  v_test_email text := 'testrestaurant@example.com';
  v_test_password text := 'TestPassword123!';
  v_restaurant_id uuid;
  v_product_id uuid;
BEGIN
  RAISE NOTICE 'Starting test data seeding...';

  -- =============================================
  -- IMPORTANT: Create auth user first
  -- =============================================
  -- In production, users are created via auth.signup()
  -- For testing, we need to insert directly into auth.users
  
  -- Check if test user already exists
  SELECT id INTO v_test_user_id
  FROM auth.users
  WHERE email = v_test_email;

  IF v_test_user_id IS NULL THEN
    -- Generate a new UUID for the test user
    v_test_user_id := gen_random_uuid();
    
    RAISE NOTICE 'Creating auth user with email: %', v_test_email;
    
    -- Insert into auth.users (this requires superuser privileges)
    -- NOTE: In a real environment, you should use auth.signup() instead
    INSERT INTO auth.users (
      id,
      instance_id,
      email,
      encrypted_password,
      email_confirmed_at,
      created_at,
      updated_at,
      raw_app_meta_data,
      raw_user_meta_data,
      is_super_admin,
      role,
      aud
    ) VALUES (
      v_test_user_id,
      '00000000-0000-0000-0000-000000000000',
      v_test_email,
      crypt(v_test_password, gen_salt('bf')), -- Encrypt password
      now(),
      now(),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      false,
      'authenticated',
      'authenticated'
    );
    
    RAISE NOTICE 'Auth user created with ID: %', v_test_user_id;
  ELSE
    RAISE NOTICE 'Auth user already exists with ID: %', v_test_user_id;
  END IF;

  -- =============================================
  -- Now create the public.users record
  -- =============================================
  INSERT INTO public.users (id, email, name, role, created_at, updated_at, email_confirm)
  VALUES (
    v_test_user_id,
    v_test_email,
    'Test Restaurant Owner',
    'restaurant',
    now(),
    now(),
    true
  )
  ON CONFLICT (id) DO UPDATE
  SET 
    email = EXCLUDED.email,
    name = EXCLUDED.name,
    role = EXCLUDED.role,
    updated_at = now();

  RAISE NOTICE 'Public user record created/updated';

  -- =============================================
  -- Create test restaurant
  -- =============================================
  v_restaurant_id := gen_random_uuid();
  
  INSERT INTO public.restaurants (
    id,
    owner_id,
    name,
    description,
    address,
    phone,
    email,
    status,
    created_at,
    updated_at,
    latitude,
    longitude
  ) VALUES (
    v_restaurant_id,
    v_test_user_id,
    'Test Restaurant',
    'A test restaurant for development',
    'Calle Test 123, Ciudad',
    '+1234567890',
    v_test_email,
    'approved',
    now(),
    now(),
    19.4326,
    -99.1332
  )
  ON CONFLICT (id) DO UPDATE
  SET
    name = EXCLUDED.name,
    updated_at = now();

  RAISE NOTICE 'Test restaurant created with ID: %', v_restaurant_id;

  -- =============================================
  -- Create test products
  -- =============================================
  v_product_id := gen_random_uuid();
  
  INSERT INTO public.products (
    id,
    restaurant_id,
    name,
    description,
    price,
    is_available,
    created_at,
    updated_at
  ) VALUES (
    v_product_id,
    v_restaurant_id,
    'Test Product',
    'A delicious test product',
    99.99,
    true,
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE
  SET
    name = EXCLUDED.name,
    updated_at = now();

  RAISE NOTICE 'Test product created with ID: %', v_product_id;

  -- =============================================
  -- Summary
  -- =============================================
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Test data seeding completed successfully!';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Test User ID: %', v_test_user_id;
  RAISE NOTICE 'Test Email: %', v_test_email;
  RAISE NOTICE 'Test Password: %', v_test_password;
  RAISE NOTICE 'Restaurant ID: %', v_restaurant_id;
  RAISE NOTICE 'Product ID: %', v_product_id;
  RAISE NOTICE '========================================';
  
END $$;
