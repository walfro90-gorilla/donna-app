# Script 4: Seed Test Data - Instructions

## Problem
The `public.users` table has a foreign key constraint that references `auth.users(id)`:
```sql
CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
```

This means you MUST create the auth user first before inserting into `public.users`.

## Solution Options

### Option 1: Use Supabase Dashboard (RECOMMENDED)
1. Go to your Supabase project dashboard
2. Navigate to **Authentication** > **Users**
3. Click **Add user** > **Create new user**
4. Enter:
   - Email: `testrestaurant@example.com`
   - Password: `TestPassword123!`
   - Check "Auto Confirm User"
5. After creating, copy the User ID (UUID)
6. Run the modified script below with that UUID

### Option 2: Use Supabase Client/API
If you have access to run code, use:
```javascript
const { data, error } = await supabase.auth.admin.createUser({
  email: 'testrestaurant@example.com',
  password: 'TestPassword123!',
  email_confirm: true
})
```

### Option 3: Modified SQL Script (After creating auth user)
After creating the auth user via Dashboard or API, run this script:

```sql
DO $$
DECLARE
  v_test_user_id uuid := 'PASTE_USER_ID_HERE'; -- Replace with actual UUID from dashboard
  v_test_email text := 'testrestaurant@example.com';
  v_restaurant_id uuid;
  v_product_id uuid;
BEGIN
  RAISE NOTICE 'Starting test data seeding for user: %', v_test_user_id;

  -- Create public.users record
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

  -- Create test restaurant
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

  -- Create test product
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

  RAISE NOTICE '========================================';
  RAISE NOTICE 'Test data seeding completed!';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Restaurant ID: %', v_restaurant_id;
  RAISE NOTICE 'Product ID: %', v_product_id;
  
END $$;
```

## Quick Fix for Current Error

1. **Create the auth user first** via Supabase Dashboard (Authentication > Users)
2. **Copy the generated User ID**
3. **Run the modified script above** with that User ID pasted in

This is the safest and most reliable approach for Supabase projects.
