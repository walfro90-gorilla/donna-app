-- Canonicalize public.submit_review RPC to avoid PostgREST overloading ambiguity (PGRST203)
-- Strategy:
-- 1) Drop ALL existing overloads of public.submit_review.
-- 2) Create a single canonical function with clear parameter names and order.
-- 3) Re-grant EXECUTE.

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'submit_review'
  LOOP
    EXECUTE format('DROP FUNCTION public.submit_review(%s)', r.args);
  END LOOP;
END $$;

-- Canonical definition
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

  -- Determine author role (EN) from users
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

  INSERT INTO public.reviews (
    order_id, author_id, author_role, subject_user_id, subject_restaurant_id, rating, comment
  ) VALUES (
    p_order_id, v_author_id, v_author_role_es, p_subject_user_id, p_subject_restaurant_id, p_rating, NULLIF(coalesce(p_comment, ''), '')
  );
END;
$$;

DO $$
BEGIN
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.submit_review(uuid, smallint, uuid, uuid, text) TO authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.submit_review(uuid, smallint, uuid, uuid, text) TO anon';
END $$;

-- Notes for clients:
-- PostgREST JSON body with named params (order irrelevant):
-- {"p_order_id":"<uuid>","p_rating":5,"p_subject_user_id":"<uuid>","p_comment":"..."}
-- or
-- {"p_order_id":"<uuid>","p_rating":5,"p_subject_restaurant_id":"<uuid>"}
