-- Clean Migration for Doa Repartos Food Delivery app
-- This migration handles existing tables, policies, and foreign key constraints properly

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create tables with IF NOT EXISTS (handles existing tables)
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  phone TEXT,
  address TEXT,
  role TEXT CHECK (role IN ('cliente', 'restaurante', 'repartidor', 'admin')) DEFAULT 'cliente',
  email_confirm BOOLEAN DEFAULT false,
  avatar_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE IF NOT EXISTS restaurants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  logo_url TEXT,
  status TEXT CHECK (status IN ('pending', 'approved', 'rejected', 'suspended')) DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  restaurant_id UUID REFERENCES restaurants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  price DECIMAL(10,2) NOT NULL,
  image_url TEXT,
  is_available BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  restaurant_id UUID REFERENCES restaurants(id) ON DELETE CASCADE,
  delivery_agent_id UUID REFERENCES users(id) ON DELETE SET NULL,
  status TEXT CHECK (status IN ('pending', 'confirmed', 'in_preparation', 'ready_for_pickup', 'out_for_delivery', 'delivered', 'cancelled')) DEFAULT 'pending',
  total_amount DECIMAL(10,2) NOT NULL,
  payment_method TEXT CHECK (payment_method IN ('card', 'cash', 'paypal')) DEFAULT 'card',
  delivery_address TEXT NOT NULL,
  delivery_latlng TEXT,
  assigned_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
  product_id UUID REFERENCES products(id) ON DELETE CASCADE,
  quantity INTEGER NOT NULL DEFAULT 1,
  price_at_time_of_order DECIMAL(10,2) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
  stripe_payment_id TEXT,
  amount DECIMAL(10,2) NOT NULL,
  status TEXT CHECK (status IN ('pending', 'succeeded', 'failed', 'cancelled')) DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create indexes with IF NOT EXISTS
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_restaurants_user_id ON restaurants(user_id);
CREATE INDEX IF NOT EXISTS idx_restaurants_status ON restaurants(status);
CREATE INDEX IF NOT EXISTS idx_products_restaurant_id ON products(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_products_is_available ON products(is_available);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_id ON orders(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_orders_delivery_agent_id ON orders(delivery_agent_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);
CREATE INDEX IF NOT EXISTS idx_orders_assigned_at ON orders(assigned_at);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_payments_order_id ON payments(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);

-- Enable RLS for all tables (safe to run multiple times)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- Drop existing policies first to avoid conflicts
DROP POLICY IF EXISTS "Users can insert their own profile" ON users;
DROP POLICY IF EXISTS "Users can view own profile" ON users;
DROP POLICY IF EXISTS "Users can update own profile" ON users;
DROP POLICY IF EXISTS "Admins can view all users" ON users;
DROP POLICY IF EXISTS "Restaurant owners can manage own restaurant" ON restaurants;
DROP POLICY IF EXISTS "Customers can view approved restaurants" ON restaurants;
DROP POLICY IF EXISTS "Admins can manage all restaurants" ON restaurants;
DROP POLICY IF EXISTS "Restaurant owners can manage products" ON products;
DROP POLICY IF EXISTS "Everyone can view available products" ON products;
DROP POLICY IF EXISTS "Customers can view own orders" ON orders;
DROP POLICY IF EXISTS "Customers can create orders" ON orders;
DROP POLICY IF EXISTS "Restaurant owners can view restaurant orders" ON orders;
DROP POLICY IF EXISTS "Restaurant owners can update order status" ON orders;
DROP POLICY IF EXISTS "Delivery agents can view assigned orders" ON orders;
DROP POLICY IF EXISTS "Delivery agents can view available orders" ON orders;
DROP POLICY IF EXISTS "Delivery agents can update assigned orders" ON orders;
DROP POLICY IF EXISTS "Admins can manage all orders" ON orders;
DROP POLICY IF EXISTS "Users can view own order items" ON order_items;
DROP POLICY IF EXISTS "Users can insert own order items" ON order_items;
DROP POLICY IF EXISTS "Restaurant owners can view restaurant order items" ON order_items;
DROP POLICY IF EXISTS "Delivery agents can view assigned order items" ON order_items;
DROP POLICY IF EXISTS "Users can view own payments" ON payments;
DROP POLICY IF EXISTS "Users can insert own payments" ON payments;
DROP POLICY IF EXISTS "System can update payment status" ON payments;
DROP POLICY IF EXISTS "Restaurant owners can view restaurant payments" ON payments;
DROP POLICY IF EXISTS "Admins can manage all payments" ON payments;

-- Now create policies fresh (this will work since we dropped them first)
-- Users table policies
CREATE POLICY "Users can insert their own profile" ON users
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can view own profile" ON users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

CREATE POLICY "Admins can view all users" ON users
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Restaurants table policies
CREATE POLICY "Restaurant owners can manage own restaurant" ON restaurants
  FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Customers can view approved restaurants" ON restaurants
  FOR SELECT USING (status = 'approved');

CREATE POLICY "Admins can manage all restaurants" ON restaurants
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Products table policies
CREATE POLICY "Restaurant owners can manage products" ON products
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM restaurants 
      WHERE restaurants.id = products.restaurant_id 
      AND restaurants.user_id = auth.uid()
    )
  );

CREATE POLICY "Everyone can view available products" ON products
  FOR SELECT USING (
    is_available = true AND
    EXISTS (
      SELECT 1 FROM restaurants 
      WHERE restaurants.id = products.restaurant_id 
      AND restaurants.status = 'approved'
    )
  );

-- Orders table policies
CREATE POLICY "Customers can view own orders" ON orders
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Customers can create orders" ON orders
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Restaurant owners can view restaurant orders" ON orders
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM restaurants 
      WHERE restaurants.id = orders.restaurant_id 
      AND restaurants.user_id = auth.uid()
    )
  );

CREATE POLICY "Restaurant owners can update order status" ON orders
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM restaurants 
      WHERE restaurants.id = orders.restaurant_id 
      AND restaurants.user_id = auth.uid()
    )
  );

CREATE POLICY "Delivery agents can view assigned orders" ON orders
  FOR SELECT USING (delivery_agent_id = auth.uid());

CREATE POLICY "Delivery agents can view available orders" ON orders
  FOR SELECT USING (
    status = 'in_preparation' AND 
    delivery_agent_id IS NULL AND
    EXISTS (
      SELECT 1 FROM users 
      WHERE id = auth.uid() AND role = 'repartidor'
    )
  );

CREATE POLICY "Delivery agents can update assigned orders" ON orders
  FOR UPDATE USING (delivery_agent_id = auth.uid());

CREATE POLICY "Admins can manage all orders" ON orders
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Order items table policies
CREATE POLICY "Users can view own order items" ON order_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM orders 
      WHERE orders.id = order_items.order_id 
      AND orders.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert own order items" ON order_items
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM orders 
      WHERE orders.id = order_items.order_id 
      AND orders.user_id = auth.uid()
    )
  );

CREATE POLICY "Restaurant owners can view restaurant order items" ON order_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM orders 
      JOIN restaurants ON restaurants.id = orders.restaurant_id
      WHERE orders.id = order_items.order_id 
      AND restaurants.user_id = auth.uid()
    )
  );

CREATE POLICY "Delivery agents can view assigned order items" ON order_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM orders 
      WHERE orders.id = order_items.order_id 
      AND orders.delivery_agent_id = auth.uid()
    )
  );

-- Payments table policies
CREATE POLICY "Users can view own payments" ON payments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM orders 
      WHERE orders.id = payments.order_id 
      AND orders.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert own payments" ON payments
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM orders 
      WHERE orders.id = payments.order_id 
      AND orders.user_id = auth.uid()
    )
  );

CREATE POLICY "System can update payment status" ON payments
  FOR UPDATE USING (true);

CREATE POLICY "Restaurant owners can view restaurant payments" ON payments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM orders 
      JOIN restaurants ON restaurants.id = orders.restaurant_id
      WHERE orders.id = payments.order_id 
      AND restaurants.user_id = auth.uid()
    )
  );

CREATE POLICY "Admins can manage all payments" ON payments
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );