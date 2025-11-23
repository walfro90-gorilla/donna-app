-- Patch: añadir bypass control a la validación de items y límites de combos
-- Ejecutar ANTES de correr el backfill 04

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_validate_combo_items_and_bounds()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_item_type text;
  v_sum int;
  v_combo_id uuid;
  v_bypass text;
BEGIN
  -- Bypass para procesos de backfill/carga masiva sin deshabilitar triggers del sistema
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

COMMIT;
