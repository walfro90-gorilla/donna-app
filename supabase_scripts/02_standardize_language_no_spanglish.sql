-- ============================================================================
-- 🗣️ PHASE 2: LANGUAGE STANDARDIZATION (NO SPANGLISH)
-- ============================================================================
-- Objetivo: Estandarizar todos los roles y estados a INGLÉS.
-- Eliminar inconsistencias (users.role vs reviews.author_role) que causan bugs.
-- ============================================================================

BEGIN;

-- 1. CORREGIR DATOS EXISTENTES (Migration)
-- Convertir cualquier 'cliente', 'restaurante', 'repartidor' a sus versiones en inglés.
-- Esto asegura que los datos históricos no rompan la app. (IMPORTANTE: Case sensitive en Postgres)

UPDATE public.reviews 
SET author_role = 'client' 
WHERE author_role = 'cliente';

UPDATE public.reviews 
SET author_role = 'restaurant' 
WHERE author_role = 'restaurante';

UPDATE public.reviews 
SET author_role = 'delivery_agent' 
WHERE author_role = 'repartidor' OR author_role = 'delivery';


-- 2. ACTUALIZAR CONSTRAINTS (La regla dura)
-- Modificar el CHECK constraint de la tabla reviews para que solo acepte inglés.

-- A) Eliminar constraint viejo (que permitía español)
-- Nota: Postgres no almacena el nombre del constraint 'inline', así que lo recreamos o 
-- borramos por nombre si sabemos cual es. Si no, usamos ALTER COLUMN.
-- Usaremos una técnica segura: borrar el check si existe y crear uno nuevo.

ALTER TABLE public.reviews 
DROP CONSTRAINT IF EXISTS reviews_author_role_check;

ALTER TABLE public.reviews 
ADD CONSTRAINT reviews_author_role_check 
CHECK (author_role IN ('client', 'restaurant', 'delivery_agent', 'admin', 'system'));


-- 3. DOCUMENTAR EL CAMBIO
COMMENT ON COLUMN public.reviews.author_role IS 'Rol del autor de la reseña. ENUM STRICT (English): client, restaurant, delivery_agent. Legacy Spanish values migrated on 2025-12-16.';

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- Try inserting bad data (should fail):
-- INSERT INTO reviews (id, order_id, author_id, author_role, rating) VALUES (uuid_generate_v4(), uuid_generate_v4(), uuid_generate_v4(), 'cliente', 5);
-- ============================================================================
