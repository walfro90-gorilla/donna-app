-- =====================================================================
-- 11_create_indexes.sql
-- Índices útiles e idempotentes en FK y campos de búsqueda comunes
-- =====================================================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='clients') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_clients_user_id ON public.clients(user_id)';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='clients' AND column_name='phone') THEN
      EXECUTE 'CREATE INDEX IF NOT EXISTS idx_clients_phone ON public.clients(phone)';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='clients' AND column_name='city') THEN
      EXECUTE 'CREATE INDEX IF NOT EXISTS idx_clients_city ON public.clients(city)';
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='restaurants') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_restaurants_user_id ON public.restaurants(user_id)';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='restaurants' AND column_name='company_name') THEN
      EXECUTE 'CREATE INDEX IF NOT EXISTS idx_restaurants_company_name ON public.restaurants(company_name)';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='restaurants' AND column_name='city') THEN
      EXECUTE 'CREATE INDEX IF NOT EXISTS idx_restaurants_city ON public.restaurants(city)';
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='delivery_agents') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_delivery_agents_user_id ON public.delivery_agents(user_id)';
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='delivery_agents' AND column_name='vehicle_type') THEN
      EXECUTE 'CREATE INDEX IF NOT EXISTS idx_delivery_agents_vehicle_type ON public.delivery_agents(vehicle_type)';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='delivery_agents' AND column_name='document_id') THEN
      EXECUTE 'CREATE UNIQUE INDEX IF NOT EXISTS uq_delivery_agents_document_id ON public.delivery_agents(document_id)';
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='users') THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='email') THEN
      EXECUTE 'CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email)';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='phone') THEN
      EXECUTE 'CREATE INDEX IF NOT EXISTS idx_users_phone ON public.users(phone)';
    END IF;
  END IF;
END $$;
