-- Safe Sample Data for Doa Repartos Food Delivery app
-- This file avoids foreign key constraint violations by removing auth.users references

-- Create a safe function to insert sample users (without auth.users dependency)
CREATE OR REPLACE FUNCTION insert_sample_user_safe(
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
  SELECT id INTO existing_user_id FROM users WHERE email = p_email;
  
  IF existing_user_id IS NOT NULL THEN
    RETURN existing_user_id;
  END IF;
  
  -- Generate a new UUID for the user
  new_user_id := gen_random_uuid();
  
  -- Insert into public.users table only (no auth.users references)
  INSERT INTO users (id, email, name, phone, address, role)
  VALUES (new_user_id, p_email, p_name, p_phone, p_address, validated_role)
  ON CONFLICT (email) DO NOTHING;
  
  RETURN new_user_id;
END;
$$ LANGUAGE plpgsql;

-- Insert sample users (safe inserts that won't conflict with foreign keys)
SELECT insert_sample_user_safe('admin@doarepartos.com', 'Admin User', '+1234567890', 'Admin Office', 'admin');
SELECT insert_sample_user_safe('restaurant1@example.com', 'Pizza Palace Owner', '+1234567891', '123 Restaurant St', 'restaurante');
SELECT insert_sample_user_safe('restaurant2@example.com', 'Burger Hub Owner', '+1234567892', '456 Food Ave', 'restaurante');
SELECT insert_sample_user_safe('delivery1@example.com', 'Carlos Repartidor', '+1234567893', '789 Delivery Lane', 'repartidor');
SELECT insert_sample_user_safe('delivery2@example.com', 'Maria Delivery', '+1234567894', '321 Driver Road', 'repartidor');
SELECT insert_sample_user_safe('customer1@example.com', 'Juan Cliente', '+1234567895', '654 Customer Blvd', 'cliente');
SELECT insert_sample_user_safe('customer2@example.com', 'Ana Buyer', '+1234567896', '987 Client Street', 'cliente');

-- Insert sample restaurants (with conflict handling)
DO $$
BEGIN
  -- Pizza Palace
  IF NOT EXISTS (SELECT 1 FROM restaurants WHERE name = 'Pizza Palace' AND user_id = (SELECT id FROM users WHERE email = 'restaurant1@example.com')) THEN
    INSERT INTO restaurants (user_id, name, description, logo_url, status)
    VALUES (
      (SELECT id FROM users WHERE email = 'restaurant1@example.com'),
      'Pizza Palace',
      'Delicious authentic Italian pizzas made with fresh ingredients',
      'https://images.unsplash.com/photo-1565299624946-b28f40a0ca4b?w=400',
      'approved'
    );
  END IF;

  -- Burger Hub
  IF NOT EXISTS (SELECT 1 FROM restaurants WHERE name = 'Burger Hub' AND user_id = (SELECT id FROM users WHERE email = 'restaurant2@example.com')) THEN
    INSERT INTO restaurants (user_id, name, description, logo_url, status)
    VALUES (
      (SELECT id FROM users WHERE email = 'restaurant2@example.com'),
      'Burger Hub',
      'Gourmet burgers and crispy fries, made to order',
      'https://images.unsplash.com/photo-1571091718767-18b5b1457add?w=400',
      'approved'
    );
  END IF;
END $$;

-- Insert sample products for Pizza Palace (with conflict handling)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM products WHERE name = 'Margherita Pizza' AND restaurant_id = (SELECT id FROM restaurants WHERE name = 'Pizza Palace')) THEN
    INSERT INTO products (restaurant_id, name, description, price, image_url, is_available)
    VALUES (
      (SELECT id FROM restaurants WHERE name = 'Pizza Palace'),
      'Margherita Pizza',
      'Classic pizza with tomato sauce, mozzarella, and fresh basil',
      12.99,
      'https://images.unsplash.com/photo-1604382354936-07c5d9983bd3?w=400',
      true
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM products WHERE name = 'Pepperoni Pizza' AND restaurant_id = (SELECT id FROM restaurants WHERE name = 'Pizza Palace')) THEN
    INSERT INTO products (restaurant_id, name, description, price, image_url, is_available)
    VALUES (
      (SELECT id FROM restaurants WHERE name = 'Pizza Palace'),
      'Pepperoni Pizza',
      'Traditional pepperoni pizza with mozzarella cheese',
      14.99,
      'https://images.unsplash.com/photo-1628840042765-356cda07504e?w=400',
      true
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM products WHERE name = 'Quattro Stagioni' AND restaurant_id = (SELECT id FROM restaurants WHERE name = 'Pizza Palace')) THEN
    INSERT INTO products (restaurant_id, name, description, price, image_url, is_available)
    VALUES (
      (SELECT id FROM restaurants WHERE name = 'Pizza Palace'),
      'Quattro Stagioni',
      'Four seasons pizza with ham, mushrooms, artichokes, and olives',
      16.99,
      'https://images.unsplash.com/photo-1565299507177-b0ac66763828?w=400',
      true
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM products WHERE name = 'Caesar Salad' AND restaurant_id = (SELECT id FROM restaurants WHERE name = 'Pizza Palace')) THEN
    INSERT INTO products (restaurant_id, name, description, price, image_url, is_available)
    VALUES (
      (SELECT id FROM restaurants WHERE name = 'Pizza Palace'),
      'Caesar Salad',
      'Fresh romaine lettuce with parmesan and Caesar dressing',
      8.99,
      'https://images.unsplash.com/photo-1546793665-c74683f339c1?w=400',
      true
    );
  END IF;
END $$;

-- Insert sample products for Burger Hub (with conflict handling)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM products WHERE name = 'Classic Burger' AND restaurant_id = (SELECT id FROM restaurants WHERE name = 'Burger Hub')) THEN
    INSERT INTO products (restaurant_id, name, description, price, image_url, is_available)
    VALUES (
      (SELECT id FROM restaurants WHERE name = 'Burger Hub'),
      'Classic Burger',
      'Beef patty with lettuce, tomato, onion, and special sauce',
      11.99,
      'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400',
      true
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM products WHERE name = 'Cheeseburger' AND restaurant_id = (SELECT id FROM restaurants WHERE name = 'Burger Hub')) THEN
    INSERT INTO products (restaurant_id, name, description, price, image_url, is_available)
    VALUES (
      (SELECT id FROM restaurants WHERE name = 'Burger Hub'),
      'Cheeseburger',
      'Classic burger with melted cheddar cheese',
      12.99,
      'https://images.unsplash.com/photo-1553979459-d2229ba7433a?w=400',
      true
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM products WHERE name = 'BBQ Bacon Burger' AND restaurant_id = (SELECT id FROM restaurants WHERE name = 'Burger Hub')) THEN
    INSERT INTO products (restaurant_id, name, description, price, image_url, is_available)
    VALUES (
      (SELECT id FROM restaurants WHERE name = 'Burger Hub'),
      'BBQ Bacon Burger',
      'Burger with BBQ sauce, crispy bacon, and onion rings',
      15.99,
      'https://images.unsplash.com/photo-1572802419224-296b0aeee0d9?w=400',
      true
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM products WHERE name = 'Crispy Fries' AND restaurant_id = (SELECT id FROM restaurants WHERE name = 'Burger Hub')) THEN
    INSERT INTO products (restaurant_id, name, description, price, image_url, is_available)
    VALUES (
      (SELECT id FROM restaurants WHERE name = 'Burger Hub'),
      'Crispy Fries',
      'Golden crispy french fries with sea salt',
      4.99,
      'https://images.unsplash.com/photo-1576107232684-1279f390859f?w=400',
      true
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM products WHERE name = 'Onion Rings' AND restaurant_id = (SELECT id FROM restaurants WHERE name = 'Burger Hub')) THEN
    INSERT INTO products (restaurant_id, name, description, price, image_url, is_available)
    VALUES (
      (SELECT id FROM restaurants WHERE name = 'Burger Hub'),
      'Onion Rings',
      'Crispy beer-battered onion rings',
      6.99,
      'https://images.unsplash.com/photo-1639024471283-03518883512d?w=400',
      true
    );
  END IF;
END $$;

-- Insert sample orders (with conflict handling)
DO $$
DECLARE
  pizza_palace_id uuid;
  burger_hub_id uuid;
  customer1_id uuid;
  customer2_id uuid;
  delivery1_id uuid;
  order1_id uuid;
  order2_id uuid;
BEGIN
  -- Get IDs for reference
  SELECT id INTO pizza_palace_id FROM restaurants WHERE name = 'Pizza Palace';
  SELECT id INTO burger_hub_id FROM restaurants WHERE name = 'Burger Hub';
  SELECT id INTO customer1_id FROM users WHERE email = 'customer1@example.com';
  SELECT id INTO customer2_id FROM users WHERE email = 'customer2@example.com';
  SELECT id INTO delivery1_id FROM users WHERE email = 'delivery1@example.com';

  -- Insert first order if it doesn't exist
  IF NOT EXISTS (SELECT 1 FROM orders WHERE user_id = customer1_id AND restaurant_id = pizza_palace_id AND total_amount = 27.98) THEN
    INSERT INTO orders (user_id, restaurant_id, delivery_agent_id, status, total_amount, payment_method, delivery_address, delivery_latlng)
    VALUES (customer1_id, pizza_palace_id, delivery1_id, 'delivered', 27.98, 'card', '654 Customer Blvd', '40.7128,-74.0060')
    RETURNING id INTO order1_id;

    -- Insert order items for first order
    INSERT INTO order_items (order_id, product_id, quantity, price_at_time_of_order)
    VALUES 
    (order1_id, (SELECT id FROM products WHERE name = 'Margherita Pizza'), 1, 12.99),
    (order1_id, (SELECT id FROM products WHERE name = 'Pepperoni Pizza'), 1, 14.99);

    -- Insert payment for first order
    INSERT INTO payments (order_id, stripe_payment_id, amount, status)
    VALUES (order1_id, 'pi_test_1234567890', 27.98, 'succeeded');
  END IF;

  -- Insert second order if it doesn't exist
  IF NOT EXISTS (SELECT 1 FROM orders WHERE user_id = customer2_id AND restaurant_id = burger_hub_id AND total_amount = 23.97) THEN
    INSERT INTO orders (user_id, restaurant_id, delivery_agent_id, status, total_amount, payment_method, delivery_address, delivery_latlng)
    VALUES (customer2_id, burger_hub_id, null, 'pending', 23.97, 'cash', '987 Client Street', '40.7589,-73.9851')
    RETURNING id INTO order2_id;

    -- Insert order items for second order
    INSERT INTO order_items (order_id, product_id, quantity, price_at_time_of_order)
    VALUES 
    (order2_id, (SELECT id FROM products WHERE name = 'Classic Burger'), 1, 11.99),
    (order2_id, (SELECT id FROM products WHERE name = 'Crispy Fries'), 1, 4.99),
    (order2_id, (SELECT id FROM products WHERE name = 'Onion Rings'), 1, 6.99);

    -- Insert payment for second order
    INSERT INTO payments (order_id, stripe_payment_id, amount, status)
    VALUES (order2_id, null, 23.97, 'pending');
  END IF;
END $$;