-- Safe backfill for products.type and products.contains based on existing combo tables
-- Run this after creating triggers, it should pass validations

-- 1) Mark products that are combos if there is a product_combos row
DO $$
BEGIN
  IF to_regclass('public.product_combos') IS NOT NULL THEN
    UPDATE public.products p
    SET type = 'combo'
    WHERE (p.type IS NULL OR p.type <> 'combo')
      AND EXISTS (
        SELECT 1 FROM public.product_combos c WHERE c.product_id = p.id
      );
  END IF;
END $$;

-- 2) Normalize legacy values: single -> principal; null/empty -> principal (only for non-combos)
UPDATE public.products p
SET type = 'principal'
WHERE (p.type IS NULL OR p.type = '' OR p.type = 'single')
  AND (p.id NOT IN (SELECT product_id FROM public.product_combos));

-- 3) Fill contains for combos from product_combo_items (distinct product ids)
DO $$
BEGIN
  IF to_regclass('public.product_combos') IS NOT NULL AND to_regclass('public.product_combo_items') IS NOT NULL THEN
    UPDATE public.products p
    SET contains = sub.comp_ids
    FROM (
      SELECT c.product_id, ARRAY_AGG(DISTINCT i.product_id) AS comp_ids
      FROM public.product_combos c
      JOIN public.product_combo_items i ON i.combo_id = c.id
      GROUP BY c.product_id
    ) sub
    WHERE p.id = sub.product_id AND p.type = 'combo';
  END IF;
END $$;
