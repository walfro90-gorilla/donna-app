-- Sistema de modificadores estructurados (estilo DoorDash)
-- Permite a restaurantes definir grupos de opciones por producto (e.g., "Elige tu salsa")
-- y a los clientes seleccionarlas al ordenar. No rompe nada existente.

-- ─── modifier_groups ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.modifier_groups (
  id             uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id     uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  name           text NOT NULL,
  description    text,
  selection_type text NOT NULL DEFAULT 'single'
                 CHECK (selection_type IN ('single', 'multiple')),
  min_selections integer NOT NULL DEFAULT 0,
  max_selections integer NOT NULL DEFAULT 1,
  is_required    boolean NOT NULL DEFAULT false,
  sort_order     integer NOT NULL DEFAULT 0,
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

-- ─── modifiers ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.modifiers (
  id           uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_id     uuid NOT NULL REFERENCES public.modifier_groups(id) ON DELETE CASCADE,
  name         text NOT NULL,
  description  text,
  price_delta  double precision NOT NULL DEFAULT 0.0,
  is_available boolean NOT NULL DEFAULT true,
  sort_order   integer NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- ─── order_item_modifiers (snapshots al momento de ordenar) ──────────────────
CREATE TABLE IF NOT EXISTS public.order_item_modifiers (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_item_id     uuid NOT NULL REFERENCES public.order_items(id) ON DELETE CASCADE,
  modifier_id       uuid REFERENCES public.modifiers(id) ON DELETE SET NULL,
  modifier_group_id uuid REFERENCES public.modifier_groups(id) ON DELETE SET NULL,
  name              text NOT NULL,
  group_name        text,
  price_delta       double precision NOT NULL DEFAULT 0.0,
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_modifier_groups_product ON public.modifier_groups(product_id);
CREATE INDEX IF NOT EXISTS idx_modifiers_group ON public.modifiers(group_id);
CREATE INDEX IF NOT EXISTS idx_order_item_modifiers_item ON public.order_item_modifiers(order_item_id);

-- ─── RLS ─────────────────────────────────────────────────────────────────────
ALTER TABLE public.modifier_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.modifiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_item_modifiers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "restaurant_own_modifier_groups" ON public.modifier_groups
  FOR ALL USING (
    product_id IN (
      SELECT p.id FROM public.products p
      JOIN public.restaurants r ON p.restaurant_id = r.id
      WHERE r.user_id = auth.uid()
    )
  );
CREATE POLICY "public_read_modifier_groups" ON public.modifier_groups
  FOR SELECT USING (is_active = true);

CREATE POLICY "restaurant_own_modifiers" ON public.modifiers
  FOR ALL USING (
    group_id IN (
      SELECT mg.id FROM public.modifier_groups mg
      JOIN public.products p ON mg.product_id = p.id
      JOIN public.restaurants r ON p.restaurant_id = r.id
      WHERE r.user_id = auth.uid()
    )
  );
CREATE POLICY "public_read_modifiers" ON public.modifiers
  FOR SELECT USING (is_available = true);

CREATE POLICY "insert_order_item_modifiers" ON public.order_item_modifiers
  FOR INSERT WITH CHECK (true);
CREATE POLICY "read_own_order_item_modifiers" ON public.order_item_modifiers
  FOR SELECT USING (
    order_item_id IN (
      SELECT oi.id FROM public.order_items oi
      JOIN public.orders o ON oi.order_id = o.id
      WHERE o.user_id = auth.uid()
    )
  );
