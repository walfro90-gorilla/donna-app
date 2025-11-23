-- SAMPLE DATA INSERTION for Doa Repartos Food Delivery App
-- This file only handles sample data insertion with proper conflict resolution

-- Sample data insertion function (handles duplicates gracefully)
CREATE OR REPLACE FUNCTION insert_sample_user(
    p_email text,
    p_name text,
    p_phone text DEFAULT NULL,
    p_address text DEFAULT NULL,
    p_role text DEFAULT 'cliente'
) RETURNS UUID AS $$
DECLARE
  existing_user_id uuid;
  new_user_id uuid;
  validated_role text;
BEGIN
  -- Validate role value
  IF p_role NOT IN ('cliente', 'restaurante', 'repartidor', 'admin') THEN
    validated_role := 'cliente';
  ELSE
    validated_role := p_role;
  END IF;
  
  -- Check if user already exists
  SELECT id INTO existing_user_id FROM public.users WHERE email = p_email;
  
  IF existing_user_id IS NOT NULL THEN
    RETURN existing_user_id;
  END IF;
  
  -- Generate a new UUID for the user
  new_user_id := gen_random_uuid();
  
  -- Insert into public.users table
  INSERT INTO public.users (id, email, name, phone, address, role)
  VALUES (new_user_id, p_email, p_name, p_phone, p_address, validated_role)
  ON CONFLICT (email) DO NOTHING;
  
  -- Return the user_id (existing or new)
  SELECT id INTO new_user_id FROM public.users WHERE email = p_email;
  RETURN new_user_id;
END;
$$ LANGUAGE plpgsql;

-- Insert sample users (safe with duplicates)
SELECT insert_sample_user('admin@doarepartos.com', 'Admin User', '+1234567890', 'Admin Office', 'admin');
SELECT insert_sample_user('restaurant1@example.com', 'Pizza Palace Owner', '+1234567891', '123 Restaurant St', 'restaurante');
SELECT insert_sample_user('restaurant2@example.com', 'Burger Hub Owner', '+1234567892', '456 Food Ave', 'restaurante');
SELECT insert_sample_user('delivery1@example.com', 'Carlos Repartidor', '+1234567893', '789 Delivery Lane', 'repartidor');
SELECT insert_sample_user('delivery2@example.com', 'Maria Delivery', '+1234567894', '321 Driver Road', 'repartidor');
SELECT insert_sample_user('customer1@example.com', 'Juan Cliente', '+1234567895', '654 Customer Blvd', 'cliente');
SELECT insert_sample_user('customer2@example.com', 'Ana Buyer', '+1234567896', '987 Client Street', 'cliente');

-- Insert sample restaurants (with proper conflict handling)
DO $$
DECLARE
  pizza_owner_id uuid;
  burger_owner_id uuid;
BEGIN
  -- Get user IDs
  SELECT id INTO pizza_owner_id FROM public.users WHERE email = 'restaurant1@example.com';
  SELECT id INTO burger_owner_id FROM public.users WHERE email = 'restaurant2@example.com';
  
  -- Pizza Palace
  IF NOT EXISTS (SELECT 1 FROM public.restaurants WHERE name = 'Pizza Palace' AND user_id = pizza_owner_id) THEN
    INSERT INTO public.restaurants (user_id, name, description, logo_url, status)
    VALUES (
      pizza_owner_id,
      'Pizza Palace',
      'Delicious authentic Italian pizzas made with fresh ingredients',
      'https://images.unsplash.com/photo-1565299624946-b28f40a0ca4b?w=400',
      'approved'
    );
  END IF;

  -- Burger Hub
  IF NOT EXISTS (SELECT 1 FROM public.restaurants WHERE name = 'Burger Hub' AND user_id = burger_owner_id) THEN
    INSERT INTO public.restaurants (user_id, name, description, logo_url, status)
    VALUES (
      burger_owner_id,
      'Burger Hub',
      'Gourmet burgers and crispy fries, made to order',
      'https://images.unsplash.com/photo-1571091718767-18b5b1457add?w=400',
      'approved'
    );
  END IF;
END $$;

-- Insert sample products for Pizza Palace
DO $$
DECLARE
  pizza_restaurant_id uuid;
BEGIN
  SELECT id INTO pizza_restaurant_id FROM public.restaurants WHERE name = 'Pizza Palace';
  
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE name = 'Margherita Pizza' AND restaurant_id = pizza_restaurant_id) THEN
    INSERT INTO public.products (restaurant_id, name, description, price, image_url, is_available)
    VALUES (
      pizza_restaurant_id,
      'Margherita Pizza',
      'Classic pizza with tomato sauce, mozzarella, and fresh basil',
      12.99,
      'https://images.unsplash.com/photo-1604382354936-07c5d9983bd3?w=400',
      true
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.products WHERE name = 'Pepperoni Pizza' AND restaurant_id = pizza_restaurant_id) THEN
    INSERT INTO public.products (restaurant_id, name, description, price, image_url, is_available)
    VALUES (
      pizza_restaurant_id,
      'Pepperoni Pizza',
      'Traditional pepperoni pizza with mozzarella cheese',
      14.99,
      'https://images.unsplash.com/photo-1628840042765-356cda07504e?w=400',
      true
    );
  END IF;
END $$;

-- Insert sample products for Burger Hub  
DO $$
DECLARE
  burger_restaurant_id uuid;
BEGIN
  SELECT id INTO burger_restaurant_id FROM public.restaurants WHERE name = 'Burger Hub';
  
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE name = 'Classic Burger' AND restaurant_id = burger_restaurant_id) THEN
    INSERT INTO public.products (restaurant_id, name, description, price, image_url, is_available)
    VALUES (
      burger_restaurant_id,
      'Classic Burger',
      'Beef patty with lettuce, tomato, onion, and special sauce',
      11.99,
      'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400',
      true
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.products WHERE name = 'Crispy Fries' AND restaurant_id = burger_restaurant_id) THEN
    INSERT INTO public.products (restaurant_id, name, description, price, image_url, is_available)
    VALUES (
      burger_restaurant_id,
      'Crispy Fries',
      'Golden crispy french fries with sea salt',
      4.99,
      'https://images.unsplash.com/photo-1576107232684-1279f390859f?w=400',
      true
    );
  END IF;
END $$;