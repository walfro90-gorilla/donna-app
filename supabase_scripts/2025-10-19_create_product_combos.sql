-- Create support for product combos (bundles)
-- Tables: product_combos, product_combo_items

CREATE TABLE IF NOT EXISTS product_combos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_product_combos_product_id ON product_combos(product_id);
CREATE INDEX IF NOT EXISTS idx_product_combos_restaurant_id ON product_combos(restaurant_id);

CREATE TABLE IF NOT EXISTS product_combo_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  combo_id UUID NOT NULL REFERENCES product_combos(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  quantity INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_combo_items_combo_id ON product_combo_items(combo_id);
CREATE INDEX IF NOT EXISTS idx_combo_items_product_id ON product_combo_items(product_id);

-- RLS policies (simple: restaurant owners can manage their combos, everyone can read to render menus)
ALTER TABLE product_combos ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_combo_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read product combos" ON product_combos;
CREATE POLICY "Anyone can read product combos" ON product_combos FOR SELECT USING (true);

DROP POLICY IF EXISTS "Anyone can read combo items" ON product_combo_items;
CREATE POLICY "Anyone can read combo items" ON product_combo_items FOR SELECT USING (true);

-- Basic insert/update/delete policies assuming auth.uid() == restaurants.user_id when owned
DROP POLICY IF EXISTS "Restaurant owners manage combos" ON product_combos;
CREATE POLICY "Restaurant owners manage combos" ON product_combos
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM restaurants r WHERE r.id = restaurant_id AND r.user_id = auth.uid()
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM restaurants r WHERE r.id = restaurant_id AND r.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Restaurant owners manage combo items" ON product_combo_items;
CREATE POLICY "Restaurant owners manage combo items" ON product_combo_items
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM product_combos c JOIN restaurants r ON r.id = c.restaurant_id
      WHERE c.id = combo_id AND r.user_id = auth.uid()
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM product_combos c JOIN restaurants r ON r.id = c.restaurant_id
      WHERE c.id = combo_id AND r.user_id = auth.uid()
    )
  );

COMMENT ON TABLE product_combos IS 'Defines combos as purchasable products via product_id';
COMMENT ON TABLE product_combo_items IS 'Items that compose a combo';
