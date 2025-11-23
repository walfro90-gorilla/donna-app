-- ============================================================================
-- 2025-11-12_16_FIX_BEFORE_trigger_bypass.sql
-- 
-- FIX DEFINITIVO: El error viene del trigger BEFORE fn_products_validate_type_contains
-- que valida contains ANTES de que la RPC pueda llenarlo.
-- 
-- SOLUCIÓN: Modificar el trigger BEFORE para RESPETAR el flag combo.bypass_validate
-- que la RPC upsert_combo_atomic ya está configurando.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_products_validate_type_contains()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  invalid_count integer;
  v_bypass text;
BEGIN
  -- BYPASS: Si la RPC upsert_combo_atomic activó el bypass, permitir contains temporalmente vacío
  v_bypass := current_setting('combo.bypass_validate', true);
  
  IF v_bypass = 'on' THEN
    -- La RPC está manejando la validación manualmente. Permitir el INSERT/UPDATE sin validación row-level
    RETURN NEW;
  END IF;

  -- Validación normal cuando NO hay bypass
  IF NEW.type::text = 'combo' THEN
    -- contains debe ser un jsonb array no vacío
    IF NEW.contains IS NULL OR jsonb_typeof(NEW.contains) <> 'array' OR jsonb_array_length(NEW.contains) = 0 THEN
      RAISE EXCEPTION 'products.contains no puede ser NULL/vacío y debe ser un arreglo JSON cuando type = combo';
    END IF;

    -- Remover auto-referencia si está presente (solo en UPDATE)
    IF NEW.id IS NOT NULL THEN
      NEW.contains := COALESCE(
        (
          SELECT jsonb_agg(elem)
          FROM jsonb_array_elements(NEW.contains) AS elem
          WHERE (
            NOT (elem ? 'product_id')
          ) OR (
            (elem->>'product_id')::uuid IS DISTINCT FROM NEW.id
          )
        ), '[]'::jsonb
      );
    END IF;

    -- Deduplicar por product_id y normalizar quantity (default 1)
    NEW.contains := COALESCE((
      WITH parsed AS (
        SELECT
          NULLIF(elem->>'product_id','') AS pid_text,
          COALESCE(NULLIF(elem->>'quantity','')::int, 1) AS qty
        FROM jsonb_array_elements(NEW.contains) AS elem
      ), valid AS (
        SELECT DISTINCT ON (pid_text)
          pid_text, qty
        FROM parsed
        WHERE pid_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        ORDER BY pid_text
      )
      SELECT jsonb_agg(jsonb_build_object('product_id', (pid_text)::uuid, 'quantity', GREATEST(qty,1)))
      FROM valid
    ), '[]'::jsonb);

    -- Validar que todos los productos referenciados existen y pertenecen al mismo restaurante
    SELECT COUNT(*) INTO invalid_count
    FROM (
      SELECT (elem->>'product_id')::uuid AS pid
      FROM jsonb_array_elements(NEW.contains) AS elem
      WHERE elem ? 'product_id'
    ) AS c
    LEFT JOIN public.products p ON p.id = c.pid
    WHERE p.id IS NULL OR p.restaurant_id <> NEW.restaurant_id;

    IF invalid_count > 0 THEN
      RAISE EXCEPTION 'products.contains incluye productos inexistentes o de otro restaurante';
    END IF;

  ELSE
    -- Para tipos no-combo, contains debe ser NULL
    NEW.contains := NULL;
  END IF;

  RETURN NEW;
END
$$;

-- Recrear el trigger (ya existe, solo actualizamos la función)
DROP TRIGGER IF EXISTS trg_products_validate_type_contains ON public.products;
CREATE TRIGGER trg_products_validate_type_contains
BEFORE INSERT OR UPDATE OF type, contains ON public.products
FOR EACH ROW EXECUTE FUNCTION public.fn_products_validate_type_contains();

COMMENT ON FUNCTION public.fn_products_validate_type_contains() IS 
'Valida products.contains para combos. Respeta flag combo.bypass_validate=on para permitir validación diferida en transacciones atómicas.';

-- Log de éxito
DO $$
BEGIN
  RAISE NOTICE '✅ Trigger BEFORE fn_products_validate_type_contains actualizado para respetar bypass flag.';
END $$;
