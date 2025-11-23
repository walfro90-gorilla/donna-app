-- =====================================================================
-- 09_update_rls_policies_v2.sql
-- Políticas RLS idempotentes y condicionales a existencia de tablas
-- • Aplica RLS para public.users, public.clients, public.restaurants, public.delivery_agents
-- • Drop IF EXISTS por nombre y Create con condiciones típicas de owner
-- =====================================================================

-- Asegura RLS activado/desactivado de forma segura si existen tablas
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='users') THEN
    EXECUTE 'ALTER TABLE public.users ENABLE ROW LEVEL SECURITY';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='clients') THEN
    EXECUTE 'ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='restaurants') THEN
    EXECUTE 'ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='delivery_agents') THEN
    EXECUTE 'ALTER TABLE public.delivery_agents ENABLE ROW LEVEL SECURITY';
  END IF;
END $$;

-- USERS policies
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='users') THEN
    -- Drops
    EXECUTE 'DROP POLICY IF EXISTS users_select_own ON public.users';
    EXECUTE 'DROP POLICY IF EXISTS users_insert_self ON public.users';
    EXECUTE 'DROP POLICY IF EXISTS users_update_own ON public.users';

    -- Creates
    EXECUTE $$CREATE POLICY users_select_own ON public.users
      FOR SELECT
      TO authenticated
      USING (id = auth.uid())$$;

    EXECUTE $$CREATE POLICY users_insert_self ON public.users
      FOR INSERT
      TO authenticated
      WITH CHECK (id = auth.uid())$$;

    EXECUTE $$CREATE POLICY users_update_own ON public.users
      FOR UPDATE
      TO authenticated
      USING (id = auth.uid())$$;
  END IF;
END $$;

-- CLIENTS policies
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='clients') THEN
    EXECUTE 'DROP POLICY IF EXISTS clients_select_own ON public.clients';
    EXECUTE 'DROP POLICY IF EXISTS clients_insert_self ON public.clients';
    EXECUTE 'DROP POLICY IF EXISTS clients_update_own ON public.clients';

    EXECUTE $$CREATE POLICY clients_select_own ON public.clients
      FOR SELECT TO authenticated
      USING (user_id = auth.uid())$$;

    EXECUTE $$CREATE POLICY clients_insert_self ON public.clients
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid())$$;

    EXECUTE $$CREATE POLICY clients_update_own ON public.clients
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())$$;
  END IF;
END $$;

-- RESTAURANTS policies
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='restaurants') THEN
    EXECUTE 'DROP POLICY IF EXISTS restaurants_select_own ON public.restaurants';
    EXECUTE 'DROP POLICY IF EXISTS restaurants_insert_self ON public.restaurants';
    EXECUTE 'DROP POLICY IF EXISTS restaurants_update_own ON public.restaurants';

    EXECUTE $$CREATE POLICY restaurants_select_own ON public.restaurants
      FOR SELECT TO authenticated
      USING (user_id = auth.uid())$$;

    EXECUTE $$CREATE POLICY restaurants_insert_self ON public.restaurants
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid())$$;

    EXECUTE $$CREATE POLICY restaurants_update_own ON public.restaurants
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())$$;
  END IF;
END $$;

-- DELIVERY_AGENTS policies
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='delivery_agents') THEN
    EXECUTE 'DROP POLICY IF EXISTS delivery_agents_select_own ON public.delivery_agents';
    EXECUTE 'DROP POLICY IF EXISTS delivery_agents_insert_self ON public.delivery_agents';
    EXECUTE 'DROP POLICY IF EXISTS delivery_agents_update_own ON public.delivery_agents';

    EXECUTE $$CREATE POLICY delivery_agents_select_own ON public.delivery_agents
      FOR SELECT TO authenticated
      USING (user_id = auth.uid())$$;

    EXECUTE $$CREATE POLICY delivery_agents_insert_self ON public.delivery_agents
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid())$$;

    EXECUTE $$CREATE POLICY delivery_agents_update_own ON public.delivery_agents
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())$$;
  END IF;
END $$;
