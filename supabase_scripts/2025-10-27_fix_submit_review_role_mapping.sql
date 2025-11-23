-- Purpose: Fix submit_review RPC inserting English roles that violate
-- reviews.author_role CHECK (expects 'cliente','restaurante','repartidor').
-- This script replaces the function to map public.users.role (EN) -> reviews.author_role (ES).
-- Idempotent: uses CREATE OR REPLACE FUNCTION.

DO $$
BEGIN
  -- Ensure table exists (context-only safeguard; will no-op if present)
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'submit_review'
  ) THEN
    RAISE NOTICE 'Creating submit_review for the first time (or replacing later)';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.submit_review(
  p_order_id uuid,
  p_subject_user_id uuid DEFAULT NULL,
  p_subject_restaurant_id uuid DEFAULT NULL,
  p_rating smallint,
  p_comment text DEFAULT ''
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_author_id uuid := auth.uid();
  v_author_role_en text;
  v_author_role_es text;
BEGIN
  IF v_author_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Validate inputs
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'p_order_id is required';
  END IF;
  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'p_rating must be between 1 and 5';
  END IF;
  IF (p_subject_user_id IS NULL AND p_subject_restaurant_id IS NULL)
     OR (p_subject_user_id IS NOT NULL AND p_subject_restaurant_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Provide either p_subject_user_id OR p_subject_restaurant_id, exclusively';
  END IF;

  -- Get author role from users (English values)
  SELECT role INTO v_author_role_en
  FROM public.users
  WHERE id = v_author_id;

  IF v_author_role_en IS NULL THEN
    -- default to client if not found
    v_author_role_en := 'client';
  END IF;

  -- Map EN -> ES for reviews.author_role
  v_author_role_es := CASE lower(v_author_role_en)
    WHEN 'client' THEN 'cliente'
    WHEN 'restaurant' THEN 'restaurante'
    WHEN 'delivery_agent' THEN 'repartidor'
    WHEN 'admin' THEN 'admin'
    ELSE 'cliente'
  END;

  -- Insert review; RLS requires author_id = auth.uid() which we satisfy
  INSERT INTO public.reviews (
    order_id, author_id, author_role, subject_user_id, subject_restaurant_id, rating, comment
  ) VALUES (
    p_order_id, v_author_id, v_author_role_es, p_subject_user_id, p_subject_restaurant_id, p_rating, NULLIF(coalesce(p_comment,''), '')
  );
END;
$$;

-- Optional: Grant execute to authenticated users
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'submit_review'
  ) THEN
    RAISE NOTICE 'submit_review not found after creation (unexpected)';
  END IF;
  -- Grant execute to authenticated and anon (if needed)
  GRANT EXECUTE ON FUNCTION public.submit_review(uuid, uuid, uuid, smallint, text) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.submit_review(uuid, uuid, uuid, smallint, text) TO anon;
END $$;
