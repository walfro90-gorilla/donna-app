-- ============================================================================
-- SCRIPT DE VERIFICACIÓN: verify_google_auth.sql
-- ============================================================================
-- Ejecuta este script DESPUÉS de registrar un nuevo usuario con Google.
-- Muestra los últimos 5 usuarios registrados para verificar que:
-- 1. name y email estén correctos en public.users
-- 2. profile_image_url esté guardado en public.client_profiles
-- ============================================================================

SELECT 
    u.id, 
    u.email, 
    u.name, 
    u.role, 
    cp.profile_image_url,
    cp.address_structured, 
    u.created_at
FROM public.users u
LEFT JOIN public.client_profiles cp ON u.id = cp.user_id
ORDER BY u.created_at DESC
LIMIT 5;

-- ============================================================================
-- Si ves la URL de la imagen en 'profile_image_url', ¡FUNCIONÓ!
-- ============================================================================
