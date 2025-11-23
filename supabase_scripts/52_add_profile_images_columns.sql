-- ============================================================================
-- Script: 52_add_profile_images_columns.sql
-- Descripción: Añade columnas para imágenes de perfil en restaurantes y repartidores
-- Autor: Sistema DOA Repartos
-- Fecha: 2025
-- ============================================================================

-- ===========================================================================
-- 1. AÑADIR COLUMNAS DE IMÁGENES A USERS
-- ===========================================================================

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS profile_image_url TEXT,
  ADD COLUMN IF NOT EXISTS id_document_front_url TEXT,
  ADD COLUMN IF NOT EXISTS id_document_back_url TEXT,
  ADD COLUMN IF NOT EXISTS vehicle_registration_url TEXT,
  ADD COLUMN IF NOT EXISTS vehicle_insurance_url TEXT,
  ADD COLUMN IF NOT EXISTS vehicle_photo_url TEXT;

COMMENT ON COLUMN public.users.profile_image_url IS 'URL de la imagen de perfil del usuario (repartidor o propietario de restaurante)';
COMMENT ON COLUMN public.users.id_document_front_url IS 'URL de la foto frontal del documento de identidad (repartidores)';
COMMENT ON COLUMN public.users.id_document_back_url IS 'URL de la foto trasera del documento de identidad (repartidores)';
COMMENT ON COLUMN public.users.vehicle_registration_url IS 'URL de la foto de registro vehicular (repartidores)';
COMMENT ON COLUMN public.users.vehicle_insurance_url IS 'URL de la foto del seguro vehicular (repartidores)';
COMMENT ON COLUMN public.users.vehicle_photo_url IS 'URL de la foto del vehículo (repartidores)';

-- ===========================================================================
-- 2. AÑADIR COLUMNAS DE IMÁGENES A RESTAURANTS
-- ===========================================================================

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS logo_url TEXT,
  ADD COLUMN IF NOT EXISTS cover_image_url TEXT,
  ADD COLUMN IF NOT EXISTS menu_image_url TEXT,
  ADD COLUMN IF NOT EXISTS business_permit_url TEXT,
  ADD COLUMN IF NOT EXISTS health_permit_url TEXT;

COMMENT ON COLUMN public.restaurants.logo_url IS 'URL del logo del restaurante';
COMMENT ON COLUMN public.restaurants.cover_image_url IS 'URL de la imagen de portada del restaurante';
COMMENT ON COLUMN public.restaurants.menu_image_url IS 'URL de la foto del menú físico';
COMMENT ON COLUMN public.restaurants.business_permit_url IS 'URL del permiso de negocio';
COMMENT ON COLUMN public.restaurants.health_permit_url IS 'URL del permiso sanitario';

-- ===========================================================================
-- 3. AÑADIR COLUMNAS ADICIONALES PARA REPARTIDORES
-- ===========================================================================

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS vehicle_type TEXT CHECK (vehicle_type IN ('bicicleta', 'motocicleta', 'auto', 'pie', 'otro')),
  ADD COLUMN IF NOT EXISTS vehicle_plate TEXT,
  ADD COLUMN IF NOT EXISTS vehicle_model TEXT,
  ADD COLUMN IF NOT EXISTS vehicle_color TEXT,
  ADD COLUMN IF NOT EXISTS emergency_contact_name TEXT,
  ADD COLUMN IF NOT EXISTS emergency_contact_phone TEXT;

COMMENT ON COLUMN public.users.vehicle_type IS 'Tipo de vehículo del repartidor';
COMMENT ON COLUMN public.users.vehicle_plate IS 'Placa del vehículo';
COMMENT ON COLUMN public.users.vehicle_model IS 'Modelo del vehículo';
COMMENT ON COLUMN public.users.vehicle_color IS 'Color del vehículo';
COMMENT ON COLUMN public.users.emergency_contact_name IS 'Nombre del contacto de emergencia';
COMMENT ON COLUMN public.users.emergency_contact_phone IS 'Teléfono del contacto de emergencia';

-- ===========================================================================
-- 4. AÑADIR COLUMNAS ADICIONALES PARA RESTAURANTES
-- ===========================================================================

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS cuisine_type TEXT,
  ADD COLUMN IF NOT EXISTS business_hours JSONB,
  ADD COLUMN IF NOT EXISTS delivery_radius_km NUMERIC(5,2) DEFAULT 5.0,
  ADD COLUMN IF NOT EXISTS min_order_amount NUMERIC(10,2) DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS estimated_delivery_time_minutes INTEGER DEFAULT 30;

COMMENT ON COLUMN public.restaurants.cuisine_type IS 'Tipo de cocina (mexicana, italiana, china, etc.)';
COMMENT ON COLUMN public.restaurants.business_hours IS 'Horarios de operación en formato JSON: {"lunes": {"open": "09:00", "close": "22:00"}, ...}';
COMMENT ON COLUMN public.restaurants.delivery_radius_km IS 'Radio de entrega en kilómetros';
COMMENT ON COLUMN public.restaurants.min_order_amount IS 'Monto mínimo de pedido';
COMMENT ON COLUMN public.restaurants.estimated_delivery_time_minutes IS 'Tiempo estimado de entrega en minutos';

-- ===========================================================================
-- 5. CREAR ÍNDICES PARA BÚSQUEDAS RÁPIDAS
-- ===========================================================================

CREATE INDEX IF NOT EXISTS idx_restaurants_cuisine_type ON public.restaurants(cuisine_type);
CREATE INDEX IF NOT EXISTS idx_users_vehicle_type ON public.users(vehicle_type) WHERE role = 'repartidor';

-- ===========================================================================
-- 6. CREAR FUNCIÓN PARA VALIDAR PERFIL COMPLETO DE REPARTIDOR
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.is_delivery_profile_complete(user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  profile_complete BOOLEAN;
BEGIN
  SELECT 
    name IS NOT NULL AND
    phone IS NOT NULL AND
    address IS NOT NULL AND
    lat IS NOT NULL AND
    lon IS NOT NULL AND
    profile_image_url IS NOT NULL AND
    id_document_front_url IS NOT NULL AND
    id_document_back_url IS NOT NULL AND
    vehicle_type IS NOT NULL AND
    vehicle_plate IS NOT NULL
  INTO profile_complete
  FROM public.users
  WHERE id = user_id AND role = 'repartidor';
  
  RETURN COALESCE(profile_complete, FALSE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.is_delivery_profile_complete IS 'Valida si el perfil de un repartidor está completo con todos los datos obligatorios';

-- ===========================================================================
-- 7. CREAR FUNCIÓN PARA VALIDAR PERFIL COMPLETO DE RESTAURANTE
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.is_restaurant_profile_complete(restaurant_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  profile_complete BOOLEAN;
BEGIN
  SELECT 
    r.name IS NOT NULL AND
    r.logo_url IS NOT NULL AND
    r.cover_image_url IS NOT NULL AND
    r.cuisine_type IS NOT NULL AND
    r.address_structured IS NOT NULL AND
    u.phone IS NOT NULL
  INTO profile_complete
  FROM public.restaurants r
  JOIN public.users u ON r.user_id = u.id
  WHERE r.id = restaurant_id;
  
  RETURN COALESCE(profile_complete, FALSE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.is_restaurant_profile_complete IS 'Valida si el perfil de un restaurante está completo con todos los datos obligatorios';

-- ===========================================================================
-- FIN DEL SCRIPT
-- ===========================================================================
