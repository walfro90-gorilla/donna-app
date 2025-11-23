-- ========================================
-- 86_sync_email_verification_status.sql
-- ========================================
-- Sincroniza el campo email_confirm en public.users
-- con el estado real de auth.users.email_confirmed_at
-- y crea una función segura para consultar el estado
-- de verificación por email.
-- ========================================

-- 1) Crear función segura para verificar email desde auth.users
CREATE OR REPLACE FUNCTION public.is_email_verified(p_email TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
  v_confirmed_at TIMESTAMPTZ;
BEGIN
  -- Buscar en auth.users el email_confirmed_at
  SELECT email_confirmed_at
  INTO v_confirmed_at
  FROM auth.users
  WHERE email = p_email
  LIMIT 1;
  
  -- Si encontró el usuario y tiene email_confirmed_at, está verificado
  RETURN (v_confirmed_at IS NOT NULL);
EXCEPTION
  WHEN OTHERS THEN
    -- En caso de error, asumir no verificado
    RETURN FALSE;
END;
$func$;

-- 2) Sincronizar todos los email_confirm en public.users
-- basándose en el estado real de auth.users
DO $do_sync$
DECLARE
  v_count INTEGER := 0;
BEGIN
  -- Actualizar users que tienen email verificado en auth pero no en public
  WITH auth_verified AS (
    SELECT u.id, u.email
    FROM auth.users u
    WHERE u.email_confirmed_at IS NOT NULL
  )
  UPDATE public.users pu
  SET 
    email_confirm = TRUE,
    updated_at = NOW()
  FROM auth_verified av
  WHERE pu.email = av.email
    AND pu.email_confirm = FALSE;
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE '✅ Sincronizados % usuarios con email verificado', v_count;
  
  -- Actualizar users que NO tienen email verificado en auth
  v_count := 0;
  WITH auth_not_verified AS (
    SELECT u.id, u.email
    FROM auth.users u
    WHERE u.email_confirmed_at IS NULL
  )
  UPDATE public.users pu
  SET 
    email_confirm = FALSE,
    updated_at = NOW()
  FROM auth_not_verified anv
  WHERE pu.email = anv.email
    AND pu.email_confirm = TRUE;
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE '✅ Sincronizados % usuarios con email NO verificado', v_count;
  
  -- 3) Crear una vista materializada opcional para mejorar performance
  -- (comentada por defecto, descomentar si hay problemas de rendimiento)
  /*
  CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_email_verification AS
  SELECT 
    u.id,
    u.email,
    (u.email_confirmed_at IS NOT NULL) AS is_verified
  FROM auth.users u;

  CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_email_verification_id ON public.mv_email_verification(id);
  CREATE INDEX IF NOT EXISTS idx_mv_email_verification_email ON public.mv_email_verification(email);

  -- Refrescar la vista cada hora
  -- (necesitarías configurar un cron job en Supabase para esto)
  -- REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_email_verification;
  */
  
  RAISE NOTICE '✅ Script 86 completado: email_confirm sincronizado y función is_email_verified() creada';
END;
$do_sync$;
