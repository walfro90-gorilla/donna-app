-- Crear tablas para combos de productos, alineado estrictamente a DATABASE_SCHEMA.sql
-- products(type product_type_enum, contains jsonb)
-- Nota: el precio del combo es fijo (products.price) y no se recalcula

BEGIN;

-- Tabla principal de combos. Cada combo corresponde a un producto en products (type='combo').
CREATE TABLE IF NOT EXISTS public.product_combos (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Un combo por producto
CREATE UNIQUE INDEX IF NOT EXISTS uq_product_combos_product_id ON public.product_combos(product_id);
CREATE INDEX IF NOT EXISTS idx_product_combos_restaurant ON public.product_combos(restaurant_id);

-- Ítems que componen el combo
CREATE TABLE IF NOT EXISTS public.product_combo_items (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  combo_id uuid NOT NULL REFERENCES public.product_combos(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  quantity integer NOT NULL DEFAULT 1 CHECK (quantity >= 1),
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_product_combo_items_combo ON public.product_combo_items(combo_id);
CREATE INDEX IF NOT EXISTS idx_product_combo_items_product ON public.product_combo_items(product_id);

COMMIT;

COMMENT ON TABLE public.product_combos IS 'Define combos como productos comprables (products.id con type=combo)';
COMMENT ON TABLE public.product_combo_items IS 'Ítems que componen un combo (sin permitir combos dentro de combos)';
