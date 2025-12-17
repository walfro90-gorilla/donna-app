-- ============================================================================
-- 📚 DOCUMENTATION AS CODE - DOÑA REPARTOS
-- ============================================================================
-- Este script aplica comentarios oficiales a las tablas y columnas críticas.
-- Sirve como la "Fuente de la Verdad" para desarrolladores y herramientas de IA.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. USERS & IDENTITY (Core)
-- ----------------------------------------------------------------------------
COMMENT ON TABLE public.users IS 'Tabla maestra de identidad. Extiende auth.users con datos públicos no sensibles.';
COMMENT ON COLUMN public.users.role IS 'ENUM (English): client, restaurant, delivery_agent, admin. CRÍTICO: Usar siempre en inglés para consistencia.';
COMMENT ON COLUMN public.users.email_confirm IS 'Flag de verificación de correo. Si es false, el usuario tiene acceso limitado.';

COMMENT ON TABLE public.client_profiles IS 'Perfil extendido para clientes (role=client). Contiene preferencias y datos de entrega.';
COMMENT ON COLUMN public.client_profiles.address_structured IS 'JSONB con desglose de Google Places (street, city, state, country, postal_code).';

COMMENT ON TABLE public.delivery_agent_profiles IS 'Perfil profesional para repartidores (role=delivery_agent). Maneja verificación legal y de vehículo.';
COMMENT ON COLUMN public.delivery_agent_profiles.status IS 'Estado de disponibilidad: offline, online, busy. Gestionado por la app móvil.';
COMMENT ON COLUMN public.delivery_agent_profiles.account_state IS 'Estado administrativo: pending (revisión), approved (puede trabajar), rejected.';

-- ----------------------------------------------------------------------------
-- 2. RESTAURANTS & CATALOG
-- ----------------------------------------------------------------------------
COMMENT ON TABLE public.restaurants IS 'Entidad de negocio/tienda. Actualmente relación 1:1 con Users (Limitación conocida - Roadmap: Multi-store).';
COMMENT ON COLUMN public.restaurants.commission_bps IS 'Comisión de plataforma en Basis Points (100 bps = 1%). Default: 1500 (15%).';
COMMENT ON COLUMN public.restaurants.online IS 'Interruptor maestro de "Tienda Abierta/Cerrada" controlado por el restaurante.';

COMMENT ON TABLE public.products IS 'Catálogo de ítems vendibles. Asociado a un restaurante.';
COMMENT ON COLUMN public.products.type IS 'Clasificación: principal, bebida, postre, combo. Usado para filtrado en UI.';
COMMENT ON COLUMN public.products.contains IS 'JSONB para Combos: lista de IDs de otros productos incluidos en este ítem.';

-- ----------------------------------------------------------------------------
-- 3. ORDERS & LOGISTICS
-- ----------------------------------------------------------------------------
COMMENT ON TABLE public.orders IS 'Tabla transaccional central. Inmutable una vez completada.';
COMMENT ON COLUMN public.orders.status IS 'Máquina de estados: pending -> confirmed -> preparing -> ready_for_pickup -> assigned -> picked_up -> on_the_way -> delivered.';
COMMENT ON COLUMN public.orders.delivery_lat IS 'Coordenada Latitud (Legacy Float). Roadmap: Migrar a PostGIS Geography.';
COMMENT ON COLUMN public.orders.delivery_fee IS 'Costo de envío calculado dinámicamente o tarifa base.';

COMMENT ON TABLE public.courier_locations_latest IS 'HOT DATA: Última ubicación conocida de cada repartidor activo. Alta frecuencia de escritura.';
COMMENT ON TABLE public.courier_locations_history IS 'COLD DATA: Historial de ruta para auditoría y reproducción de viajes.';

-- ----------------------------------------------------------------------------
-- 4. FINANCIAL LEDGER (Double-Entry)
-- ----------------------------------------------------------------------------
COMMENT ON TABLE public.accounts IS 'Billeteras/Cuentas del sistema financiero interno (Ledger).';
COMMENT ON COLUMN public.accounts.account_type IS 'Tipos: client, restaurant, delivery_agent, platform_revenue (Ganancias App), platform_payables (Deudas App).';
COMMENT ON COLUMN public.accounts.balance IS 'Saldo actual. Debe coincidir SIEMPRE con la suma de account_transactions.';

COMMENT ON TABLE public.account_transactions IS 'Libro mayor inmutable. Cada movimiento de dinero DEBE registrarse aquí.';
COMMENT ON COLUMN public.account_transactions.type IS 'Tipos: ORDER_REVENUE (Venta), PLATFORM_COMMISSION (Nuestra ganancia), DELIVERY_EARNING (Ganancia repartidor).';

-- ----------------------------------------------------------------------------
-- 5. REVIEWS & QUALITY
-- ----------------------------------------------------------------------------
COMMENT ON TABLE public.reviews IS 'Sistema de calificación bilateral (Cliente <-> Restaurante <-> Repartidor).';
COMMENT ON COLUMN public.reviews.author_role IS 'DEPRECATED SPANGLISH: cliente, restaurante. Roadmap: Migrar a valores en inglés (client, restaurant) para consistencia.';

-- ============================================================================
-- FIN DE DOCUMENTACIÓN
-- Ejecutar en SQL Editor de Supabase para oficializar.
-- ============================================================================
