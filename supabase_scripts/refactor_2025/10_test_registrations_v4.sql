-- =====================================================================
-- 10_test_registrations_v4.sql
-- Pruebas end-to-end en SQL Editor emulando JWT claims para auth.uid()
-- • No usa RAISE fuera de DO; resultados visibles con SELECT al final
-- • Crea 3 usuarios de prueba (solo en contexto), invoca RPCs, y consulta estado
-- =====================================================================

-- Requisitos: gen_random_uuid() disponible (pgcrypto). Si no, habilitar extensión.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Variables de prueba
WITH vars AS (
  SELECT
    gen_random_uuid() AS client_uid,
    gen_random_uuid() AS restaurant_uid,
    gen_random_uuid() AS courier_uid
)
SELECT * FROM vars; -- Visualizar UIDs de prueba

-- 1) Test: register_client
DO $$
DECLARE
  v_uid uuid;
BEGIN
  SELECT gen_random_uuid() INTO v_uid;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);

  -- Llamada al RPC (firma flexible con defaults)
  PERFORM public.register_client(
    p_name    => 'Juan Pérez',
    p_phone   => '+521234567890',
    p_email   => 'juan.perez@example.com',
    p_country => 'MX',
    p_city    => 'CDMX',
    p_lat     => 19.4326,
    p_lng     => -99.1332,
    p_address => '{"street":"Av Reforma","city":"CDMX"}'::jsonb
  );

  -- Limpia claims
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 2) Test: register_restaurant
DO $$
DECLARE
  v_uid uuid;
BEGIN
  SELECT gen_random_uuid() INTO v_uid;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);

  PERFORM public.register_restaurant(
    p_company_name => 'Taquería La Estrella',
    p_contact_name => 'María López',
    p_phone        => '+525512345678',
    p_email        => 'contacto@taq-estrella.mx',
    p_lat          => 19.40,
    p_lng          => -99.16,
    p_address      => '{"street":"Insurgentes","city":"CDMX"}'::jsonb
  );

  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 3) Test: register_delivery_agent
DO $$
DECLARE
  v_uid uuid;
BEGIN
  SELECT gen_random_uuid() INTO v_uid;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);

  PERFORM public.register_delivery_agent(
    p_name         => 'Carlos Rojas',
    p_phone        => '+525511112222',
    p_email        => 'carlos.rojas@example.com',
    p_document_id  => 'INE-ABC123456',
    p_vehicle_type => 'bike',
    p_lat          => 19.45,
    p_lng          => -99.20,
    p_address      => '{"neighborhood":"Centro"}'::jsonb
  );

  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- Resultados visibles
-- Muestran conteos y algunas filas recientes si existen las tablas
SELECT 'users_count' AS metric, COUNT(*)::text AS value FROM public.users
UNION ALL
SELECT 'clients_count', COUNT(*)::text FROM public.clients WHERE user_id IS NOT NULL
UNION ALL
SELECT 'restaurants_count', COUNT(*)::text FROM public.restaurants WHERE user_id IS NOT NULL
UNION ALL
SELECT 'delivery_agents_count', COUNT(*)::text FROM public.delivery_agents WHERE user_id IS NOT NULL;

-- Muestras (limitar 5)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='users') THEN
    EXECUTE 'SELECT * FROM public.users ORDER BY created_at DESC NULLS LAST LIMIT 5';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='clients') THEN
    EXECUTE 'SELECT * FROM public.clients ORDER BY created_at DESC NULLS LAST LIMIT 5';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='restaurants') THEN
    EXECUTE 'SELECT * FROM public.restaurants ORDER BY created_at DESC NULLS LAST LIMIT 5';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='delivery_agents') THEN
    EXECUTE 'SELECT * FROM public.delivery_agents ORDER BY created_at DESC NULLS LAST LIMIT 5';
  END IF;
END $$;
