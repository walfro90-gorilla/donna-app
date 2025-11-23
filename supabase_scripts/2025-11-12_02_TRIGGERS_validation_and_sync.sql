-- Validaciones de negocio y sincronización con products.contains (jsonb)
-- Reglas:
--  - product_combos.product_id debe referir a un products.type = 'combo'
--  - product_combo_items.product_id NO puede ser combo (prohibido anidar combos)
--  - Total de unidades por combo (suma de quantities) entre 2 y 9
--  - Mantener products.contains sincronizado con product_combo_items y viceversa, sin loops

BEGIN;

-- 0) Helper: set updated_at en product_combos
CREATE OR REPLACE FUNCTION public.fn_product_combos_touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_product_combos_touch ON public.product_combos;
CREATE TRIGGER trg_product_combos_touch
BEFORE UPDATE ON public.product_combos
FOR EACH ROW EXECUTE FUNCTION public.fn_product_combos_touch_updated_at();

-- 1) Validar que product_combos.product_id sea un producto de tipo 'combo'
CREATE OR REPLACE FUNCTION public.fn_validate_product_combos_type()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_type_text text;
  v_restaurant uuid;
BEGIN
  SELECT p.type::text, p.restaurant_id INTO v_type_text, v_restaurant FROM public.products p WHERE p.id = NEW.product_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Producto % no existe', NEW.product_id;
  END IF;
  IF v_type_text <> 'combo' THEN
    RAISE EXCEPTION 'El producto % no es de tipo combo', NEW.product_id;
  END IF;
  -- Alinear restaurant_id automáticamente si difiere
  IF NEW.restaurant_id IS DISTINCT FROM v_restaurant THEN
    NEW.restaurant_id := v_restaurant;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_validate_product_combos_type ON public.product_combos;
CREATE TRIGGER trg_validate_product_combos_type
BEFORE INSERT OR UPDATE OF product_id, restaurant_id ON public.product_combos
FOR EACH ROW EXECUTE FUNCTION public.fn_validate_product_combos_type();

-- 2) Validar que los items no sean combos y respeten límites 2..9 en total
CREATE OR REPLACE FUNCTION public.fn_validate_combo_items_and_bounds()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_item_type text;
  v_sum int;
  v_combo_id uuid;
  v_bypass text;
BEGIN
  -- Bypass control para cargas por lote/backfill sin tocar triggers del sistema
  v_bypass := current_setting('combo.bypass_validate', true);
  IF v_bypass = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  v_combo_id := COALESCE(NEW.combo_id, OLD.combo_id);

  -- Validar item no es combo
  IF TG_OP <> 'DELETE' THEN
    SELECT p.type::text INTO v_item_type FROM public.products p WHERE p.id = NEW.product_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Producto % (ítem) no existe', NEW.product_id;
    END IF;
    IF v_item_type = 'combo' THEN
      RAISE EXCEPTION 'No se permiten combos dentro de combos (product_id=%)', NEW.product_id;
    END IF;
  END IF;

  -- Validar límites de cantidad total por combo (2..9)
  SELECT COALESCE(SUM(quantity), 0) INTO v_sum FROM public.product_combo_items WHERE combo_id = v_combo_id;
  IF TG_OP = 'INSERT' THEN
    v_sum := v_sum + COALESCE(NEW.quantity, 1);
  ELSIF TG_OP = 'UPDATE' THEN
    v_sum := v_sum - COALESCE(OLD.quantity, 1) + COALESCE(NEW.quantity, 1);
  ELSIF TG_OP = 'DELETE' THEN
    v_sum := v_sum - COALESCE(OLD.quantity, 1);
  END IF;

  IF v_sum < 2 OR v_sum > 9 THEN
    RAISE EXCEPTION 'Un combo debe tener entre 2 y 9 unidades en total (actual=%)', v_sum;
  END IF;

  RETURN COALESCE(NEW, OLD);
END $$;

DROP TRIGGER IF EXISTS trg_validate_combo_items_and_bounds_i ON public.product_combo_items;
DROP TRIGGER IF EXISTS trg_validate_combo_items_and_bounds_u ON public.product_combo_items;
DROP TRIGGER IF EXISTS trg_validate_combo_items_and_bounds_d ON public.product_combo_items;

CREATE TRIGGER trg_validate_combo_items_and_bounds_i
BEFORE INSERT ON public.product_combo_items
FOR EACH ROW EXECUTE FUNCTION public.fn_validate_combo_items_and_bounds();

CREATE TRIGGER trg_validate_combo_items_and_bounds_u
BEFORE UPDATE ON public.product_combo_items
FOR EACH ROW EXECUTE FUNCTION public.fn_validate_combo_items_and_bounds();

CREATE TRIGGER trg_validate_combo_items_and_bounds_d
BEFORE DELETE ON public.product_combo_items
FOR EACH ROW EXECUTE FUNCTION public.fn_validate_combo_items_and_bounds();

-- 3) Sincronización: productos.contains -> combo tables (REPLACE) con guard de recursión
CREATE OR REPLACE FUNCTION public.fn_products_sync_combo_meta()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  combo_rec record;
  prev_guard text;
BEGIN
  IF to_regclass('public.product_combos') IS NULL OR to_regclass('public.product_combo_items') IS NULL THEN
    RETURN NEW;
  END IF;

  -- Si otro trigger viene sincronizando desde items -> productos, no procesar para evitar loop
  prev_guard := current_setting('combo.sync', true);
  IF prev_guard = 'from_items' THEN
    RETURN NEW;
  END IF;

  -- Marcar guardia para evitar ciclo inverso
  PERFORM set_config('combo.sync', 'from_products', true);

  IF NEW.type::text = 'combo' THEN
    SELECT * INTO combo_rec FROM public.product_combos WHERE product_id = NEW.id;
    IF NOT FOUND THEN
      INSERT INTO public.product_combos (product_id, restaurant_id)
      VALUES (NEW.id, NEW.restaurant_id);
      SELECT * INTO combo_rec FROM public.product_combos WHERE product_id = NEW.id;
    END IF;

    -- Reemplazar items por lo que venga en contains
    DELETE FROM public.product_combo_items WHERE combo_id = combo_rec.id;
    IF NEW.contains IS NOT NULL AND jsonb_typeof(NEW.contains) = 'array' AND jsonb_array_length(NEW.contains) > 0 THEN
      INSERT INTO public.product_combo_items (combo_id, product_id, quantity)
      SELECT combo_rec.id,
             (elem->>'product_id')::uuid,
             GREATEST(COALESCE(NULLIF(elem->>'quantity','')::int, 1), 1)
      FROM jsonb_array_elements(NEW.contains) AS elem
      WHERE elem ? 'product_id';
    END IF;
  ELSE
    DELETE FROM public.product_combos WHERE product_id = NEW.id;
  END IF;

  -- Limpiar guardia
  PERFORM set_config('combo.sync', '', true);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_products_sync_combo_meta ON public.products;
CREATE TRIGGER trg_products_sync_combo_meta
AFTER INSERT OR UPDATE OF type, contains ON public.products
FOR EACH ROW EXECUTE FUNCTION public.fn_products_sync_combo_meta();

-- 4) Sincronización inversa: combo items -> products.contains (solo combos)
CREATE OR REPLACE FUNCTION public.fn_combo_items_sync_products_contains()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_product_id uuid;
  v_json jsonb;
  prev_guard text;
BEGIN
  -- Evitar loop si venimos desde productos -> combos
  prev_guard := current_setting('combo.sync', true);
  IF prev_guard = 'from_products' THEN
    RETURN NULL; -- no hacer nada
  END IF;

  -- Guard de recursión
  PERFORM set_config('combo.sync', 'from_items', true);

  SELECT c.product_id INTO v_product_id FROM public.product_combos c WHERE c.id = COALESCE(NEW.combo_id, OLD.combo_id);
  IF NOT FOUND THEN
    PERFORM set_config('combo.sync', '', true);
    RETURN NULL;
  END IF;

  -- Construir JSONB contains a partir de items actuales
  SELECT COALESCE(jsonb_agg(jsonb_build_object('product_id', i.product_id, 'quantity', GREATEST(i.quantity,1))), '[]'::jsonb)
  INTO v_json
  FROM public.product_combo_items i
  WHERE i.combo_id = COALESCE(NEW.combo_id, OLD.combo_id);

  -- Actualizar products.contains solo si el producto es realmente combo
  UPDATE public.products p
  SET contains = CASE WHEN p.type::text = 'combo' THEN v_json ELSE NULL END,
      updated_at = now()
  WHERE p.id = v_product_id;

  PERFORM set_config('combo.sync', '', true);
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_combo_items_sync_products_i ON public.product_combo_items;
DROP TRIGGER IF EXISTS trg_combo_items_sync_products_u ON public.product_combo_items;
DROP TRIGGER IF EXISTS trg_combo_items_sync_products_d ON public.product_combo_items;

CREATE TRIGGER trg_combo_items_sync_products_i
AFTER INSERT ON public.product_combo_items
FOR EACH ROW EXECUTE FUNCTION public.fn_combo_items_sync_products_contains();

CREATE TRIGGER trg_combo_items_sync_products_u
AFTER UPDATE ON public.product_combo_items
FOR EACH ROW EXECUTE FUNCTION public.fn_combo_items_sync_products_contains();

CREATE TRIGGER trg_combo_items_sync_products_d
AFTER DELETE ON public.product_combo_items
FOR EACH ROW EXECUTE FUNCTION public.fn_combo_items_sync_products_contains();

COMMIT;
