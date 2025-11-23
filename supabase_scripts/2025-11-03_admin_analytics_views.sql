 -- Admin analytics views (safe defaults, align with your schema before running)
 -- If any table/column differs, please adjust per docs/admin_panel_plan.md (section 7)

 -- 0) Notes
 -- - Uses CREATE OR REPLACE VIEW for idempotency
 -- - Avoids engine-specific features; no IF NOT EXISTS on views
 -- - Time window defaults to last 30 days where applicable

 -- 1) Daily orders & GMV
 CREATE OR REPLACE VIEW public.vw_admin_orders_daily AS
 SELECT
   date_trunc('day', o.created_at)::date AS day,
   COUNT(*) AS orders_total,
   COUNT(*) FILTER (WHERE o.status = 'delivered') AS orders_delivered,
   COUNT(*) FILTER (WHERE o.status = 'canceled' OR o.status = 'cancelled') AS orders_canceled,
   COALESCE(SUM(o.total_amount), 0)::numeric AS gmv_total
 FROM public.orders o
 GROUP BY 1
 ORDER BY 1 DESC;

 COMMENT ON VIEW public.vw_admin_orders_daily IS 'Pedidos por día y GMV (suma de orders.total_amount).';

 -- 2) Restaurant KPIs (last 30d)
 CREATE OR REPLACE VIEW public.vw_admin_restaurant_kpis_30d AS
 WITH last30 AS (
   SELECT * FROM public.orders o
   WHERE o.created_at >= now() - interval '30 days'
 )
 SELECT
   r.id AS restaurant_id,
   r.name AS restaurant_name,
   COUNT(l.id) AS orders_30d,
   COALESCE(SUM(l.total_amount), 0)::numeric AS gmv_30d,
   CASE WHEN COUNT(l.id) > 0 THEN (COALESCE(SUM(l.total_amount),0) / COUNT(l.id)) ELSE 0 END::numeric AS aov_30d,
   COALESCE(AVG(rr.rating)::numeric, 0) AS avg_rating,
   COUNT(l.id) FILTER (WHERE l.status = 'canceled' OR l.status = 'cancelled') AS cancels_30d
 FROM public.restaurants r
 LEFT JOIN last30 l ON l.restaurant_id = r.id
 LEFT JOIN public.reviews rr ON rr.subject_restaurant_id = r.id
 GROUP BY r.id, r.name
 ORDER BY gmv_30d DESC;

 COMMENT ON VIEW public.vw_admin_restaurant_kpis_30d IS 'KPIs por restaurante en últimos 30 días: órdenes, GMV, AOV, rating, cancelaciones.';

 -- 3) Delivery KPIs (last 30d)
 CREATE OR REPLACE VIEW public.vw_admin_delivery_kpis_30d AS
 WITH last30 AS (
   SELECT * FROM public.orders o
   WHERE o.created_at >= now() - interval '30 days'
 )
 SELECT
   u.id AS delivery_user_id,
   COALESCE(u.name, u.email) AS delivery_name,
   COUNT(l.id) FILTER (WHERE l.status = 'delivered') AS delivered_30d,
   COUNT(l.id) FILTER (WHERE l.status = 'canceled' OR l.status = 'cancelled') AS cancelled_30d,
   COALESCE(SUM(atx.amount) FILTER (WHERE atx.type = 'DELIVERY_EARNING'), 0)::numeric AS earnings_30d
 FROM (SELECT DISTINCT delivery_agent_id FROM last30 WHERE delivery_agent_id IS NOT NULL) d
 JOIN public.users u ON u.id = d.delivery_agent_id
 LEFT JOIN last30 l ON l.delivery_agent_id = u.id
 LEFT JOIN public.accounts acc ON acc.user_id = u.id AND acc.account_type = 'delivery_agent'
 LEFT JOIN public.account_transactions atx ON atx.account_id = acc.id AND atx.created_at >= now() - interval '30 days'
 GROUP BY u.id, u.name, u.email
 ORDER BY delivered_30d DESC;

 COMMENT ON VIEW public.vw_admin_delivery_kpis_30d IS 'KPIs de repartidores 30 días: entregas, cancelaciones y ganancias.';

 -- 4) Product sales (last 30d)
 CREATE OR REPLACE VIEW public.vw_admin_product_sales_30d AS
 SELECT
   p.id AS product_id,
   p.restaurant_id,
   p.name AS product_name,
   SUM(oi.quantity) AS units_30d,
   SUM(oi.quantity * oi.price_at_time_of_order)::numeric AS revenue_30d
 FROM public.order_items oi
 JOIN public.orders o ON o.id = oi.order_id AND o.created_at >= now() - interval '30 days'
 JOIN public.products p ON p.id = oi.product_id
 GROUP BY p.id, p.restaurant_id, p.name
 ORDER BY revenue_30d DESC;

 COMMENT ON VIEW public.vw_admin_product_sales_30d IS 'Ventas por producto últimos 30 días (unidades y revenue).';

 -- 5) Finance balances snapshot
 CREATE OR REPLACE VIEW public.vw_finance_balances AS
 SELECT
   acc.id AS account_id,
   acc.user_id,
   acc.account_type,
   acc.balance,
   (SELECT atx.created_at FROM public.account_transactions atx WHERE atx.account_id = acc.id ORDER BY atx.created_at DESC LIMIT 1) AS last_tx_at
 FROM public.accounts acc;

 COMMENT ON VIEW public.vw_finance_balances IS 'Snapshot de balances por cuenta y fecha de última transacción.';

 -- Index suggestions (optional) - review before applying
 -- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_restaurant_created ON public.orders(restaurant_id, created_at DESC);
 -- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_order_items_product_created ON public.order_items(product_id, created_at DESC);
 -- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reviews_subject_restaurant_created ON public.reviews(subject_restaurant_id, created_at DESC);
 -- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_account_tx_account_created ON public.account_transactions(account_id, created_at DESC);
