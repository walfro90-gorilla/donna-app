-- =====================================================
-- 95_ensure_user_profile_public.sql
-- Crea una RPC idempotente para garantizar el perfil en public.users
-- Útil para flujos OAuth donde el trigger de auth.users no se ejecutó
-- =====================================================

DO $$
BEGIN
  -- Asegurar extensión uuid-ossp si fuera necesaria (no falla si existe)
  BEGIN
    PERFORM 1 FROM pg_extension WHERE extname = 'uuid-ossp';
  EXCEPTION WHEN others THEN
    -- ignorar
  END;
END $$;

-- RPC idempotente: crea el perfil si no existe; si existe, retorna success=true
CREATE OR REPLACE FUNCTION public.ensure_user_profile_public(
  p_user_id UUID,
  p_email TEXT,
  p_name TEXT DEFAULT NULL,
  p_role TEXT DEFAULT 'client'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_exists boolean;
BEGIN
  -- Validar identidad
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id is required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User ID % does not exist in auth.users', p_user_id;
  END IF;

  -- ¿Ya existe perfil?
  SELECT EXISTS(SELECT 1 FROM public.users WHERE id = p_user_id) INTO v_exists;

  IF NOT v_exists THEN
    INSERT INTO public.users (
      id, email, name, role, email_confirm, created_at, updated_at
    ) VALUES (
      p_user_id,
      COALESCE(p_email, ''),
      COALESCE(p_name, ''),
      COALESCE(p_role, 'client'),
      true,                    -- OAuth suele venir verificado
      NOW(),
      NOW()
    );
    RETURN jsonb_build_object('success', true, 'created', true, 'user_id', p_user_id);
  END IF;

  RETURN jsonb_build_object('success', true, 'created', false, 'user_id', p_user_id);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- Permisos de ejecución
GRANT EXECUTE ON FUNCTION public.ensure_user_profile_public(UUID, TEXT, TEXT, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.ensure_user_profile_public(UUID, TEXT, TEXT, TEXT) TO authenticated;

-- Notas:
-- - Esta función es idempotente y se puede invocar en cada login.
-- - No modifica datos existentes salvo crear el perfil la primera vez.
-- - Si tu política de negocio requiere email_confirm=false por defecto,
--   ajusta el valor de email_confirm en el INSERT.
