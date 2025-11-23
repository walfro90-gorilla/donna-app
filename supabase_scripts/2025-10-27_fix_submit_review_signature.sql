-- Fix submit_review RPC: reorder parameters to satisfy Postgres rule
-- "input parameters after one with a default value must also have defaults".
-- We move non-default params first, then params with DEFAULT at the end.
-- Also refresh GRANTs to match the new signature.

-- Drop previous broken/old signature if it exists (safe no-op if not present)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'submit_review'
      AND pg_get_function_identity_arguments(p.oid) = 'uuid, uuid, uuid, smallint, text'
  ) THEN
    EXECUTE 'DROP FUNCTION public.submit_review(uuid, uuid, uuid, smallint, text)';
  END IF;
END $$;

-- Corrected function: non-defaults first, defaults last
CREATE OR REPLACE FUNCTION public.submit_review(
  p_order_id uuid,
  p_rating smallint,
  p_subject_user_id uuid DEFAULT NULL,
  p_subject_restaurant_id uuid DEFAULT NULL,
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

  -- Insert review; RLS requires author_id = auth.uid()
  INSERT INTO public.reviews (
    order_id, author_id, author_role, subject_user_id, subject_restaurant_id, rating, comment
  ) VALUES (
    p_order_id, v_author_id, v_author_role_es, p_subject_user_id, p_subject_restaurant_id, p_rating, NULLIF(coalesce(p_comment, ''), '')
  );
END;
$$;

-- Refresh GRANTs for the new exact signature
DO $$
BEGIN
  -- Allow both anon and authenticated to call if your RLS handles auth inside
  -- Adjust as needed for your project
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.submit_review(uuid, smallint, uuid, uuid, text) TO authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.submit_review(uuid, smallint, uuid, uuid, text) TO anon';
END $$;

-- Notes for API callers (PostgREST):
-- Call with named params; order is irrelevant when using JSON RPC:
--   rpc: submit_review
--   {"p_order_id":"<uuid>","p_rating":5,"p_subject_user_id":"<uuid>","p_comment":"..."}
-- or for restaurant subject:
--   {"p_order_id":"<uuid>","p_rating":4,"p_subject_restaurant_id":"<uuid>"}
