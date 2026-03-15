-- Fix: submit_review was mapping roles to Spanish (repartidor, cliente, restaurante)
-- but the reviews_author_role_check constraint was updated to English values
-- (client, restaurant, delivery_agent, admin, system) by 02_standardize_language_no_spanglish.sql
-- This replaces the function to insert English values directly.

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
  v_author_role text;
BEGIN
  IF v_author_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

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

  -- Get author role in English directly from users table
  SELECT role INTO v_author_role
  FROM public.users
  WHERE id = v_author_id;

  -- Fallback and normalize
  v_author_role := COALESCE(lower(v_author_role), 'client');

  -- Ensure value matches the constraint: client, restaurant, delivery_agent, admin, system
  IF v_author_role NOT IN ('client', 'restaurant', 'delivery_agent', 'admin', 'system') THEN
    v_author_role := 'client';
  END IF;

  INSERT INTO public.reviews (
    order_id, author_id, author_role, subject_user_id, subject_restaurant_id, rating, comment
  ) VALUES (
    p_order_id,
    v_author_id,
    v_author_role,
    p_subject_user_id,
    p_subject_restaurant_id,
    p_rating,
    NULLIF(COALESCE(p_comment, ''), '')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_review(uuid, smallint, uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_review(uuid, smallint, uuid, uuid, text) TO anon;
