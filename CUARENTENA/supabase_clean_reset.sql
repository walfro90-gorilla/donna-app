-- ===================================================================
-- RESET COMPLETO DE LA BASE DE DATOS - OPCIÓN LIMPIA
-- ===================================================================
-- ⚠️  ADVERTENCIA: ESTO BORRARÁ TODOS LOS DATOS EXISTENTES
-- ===================================================================

-- 1️⃣ ELIMINAR TODAS LAS TABLAS RELACIONADAS CON LA APP (si existen)
-- ===================================================================
DROP TABLE IF EXISTS order_status_updates CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS restaurants CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;

-- 2️⃣ CREAR TABLA DE USUARIOS
-- ===================================================================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    phone TEXT,
    address TEXT,
    user_type TEXT NOT NULL CHECK (user_type IN ('client', 'restaurant', 'delivery', 'admin')),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3️⃣ CREAR TABLA DE RESTAURANTES
-- ===================================================================
CREATE TABLE restaurants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    address TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    image_url TEXT,
    is_active BOOLEAN DEFAULT true,
    owner_id UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4️⃣ CREAR TABLA DE PRODUCTOS
-- ===================================================================
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID REFERENCES restaurants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    price NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    image_url TEXT,
    is_available BOOLEAN DEFAULT true,
    category TEXT DEFAULT 'general',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5️⃣ CREAR TABLA DE ÓRDENES CON TODOS LOS ESTADOS REQUERIDOS
-- ===================================================================
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID REFERENCES users(id) ON DELETE CASCADE,
    restaurant_id UUID REFERENCES restaurants(id) ON DELETE CASCADE,
    delivery_agent_id UUID REFERENCES users(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'confirmed', 'preparing', 'ready', 
        'assigned', 'picked_up', 'delivered', 'cancelled'
    )),
    total_amount NUMERIC(10,2) NOT NULL CHECK (total_amount >= 0),
    delivery_fee NUMERIC(10,2) DEFAULT 0 CHECK (delivery_fee >= 0),
    delivery_address TEXT NOT NULL,
    client_phone TEXT,
    notes TEXT,
    
    -- Timestamps para tracking
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    assigned_at TIMESTAMP WITH TIME ZONE,
    pickup_time TIMESTAMP WITH TIME ZONE,
    delivery_time TIMESTAMP WITH TIME ZONE
);

-- 6️⃣ CREAR TABLA DE ITEMS DE ORDEN
-- ===================================================================
CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    subtotal NUMERIC(10,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 7️⃣ CREAR TABLA DE HISTORIAL DE CAMBIOS DE STATUS
-- ===================================================================
CREATE TABLE order_status_updates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
    previous_status TEXT,
    new_status TEXT NOT NULL,
    changed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    notes TEXT
);

-- 8️⃣ CREAR FUNCIÓN TRIGGER PARA AUTO-TRACKING DE STATUS
-- ===================================================================
CREATE OR REPLACE FUNCTION track_order_status_changes()
RETURNS TRIGGER AS $$
BEGIN
    -- Solo insertar si el status realmente cambió
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO order_status_updates (
            order_id, 
            previous_status, 
            new_status, 
            changed_at
        ) VALUES (
            NEW.id, 
            OLD.status, 
            NEW.status, 
            NOW()
        );
        
        -- Actualizar timestamps específicos según el nuevo status
        IF NEW.status = 'assigned' AND OLD.status != 'assigned' THEN
            NEW.assigned_at = NOW();
        ELSIF NEW.status = 'picked_up' AND OLD.status != 'picked_up' THEN
            NEW.pickup_time = NOW();
        ELSIF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
            NEW.delivery_time = NOW();
        END IF;
    END IF;
    
    -- Siempre actualizar updated_at
    NEW.updated_at = NOW();
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 9️⃣ CREAR EL TRIGGER
-- ===================================================================
CREATE TRIGGER orders_status_tracking_trigger
    BEFORE UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION track_order_status_changes();

-- 🔟 CONFIGURAR ROW LEVEL SECURITY (RLS)
-- ===================================================================
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_status_updates ENABLE ROW LEVEL SECURITY;

-- Políticas básicas (pueden ajustarse según necesidades)
CREATE POLICY "Users can view own data" ON users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Public can view restaurants" ON restaurants FOR SELECT USING (is_active = true);
CREATE POLICY "Public can view products" ON products FOR SELECT USING (is_available = true);
CREATE POLICY "Users can view own orders" ON orders FOR SELECT USING (auth.uid() = client_id OR auth.uid() = delivery_agent_id);
CREATE POLICY "Users can view order items" ON order_items FOR SELECT USING (true);
CREATE POLICY "Users can view status updates" ON order_status_updates FOR SELECT USING (true);

-- ===================================================================
-- ✅ SCRIPT COMPLETADO - BASE DE DATOS LIMPIA Y LISTA
-- ===================================================================