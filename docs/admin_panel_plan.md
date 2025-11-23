 # Admin Panel Revamp: Full‑Stack Plan (Aligned to Current Schema)

 Este documento propone un rediseño profesional del panel de administración para gestionar toda la operación sin tocar la base de datos directamente. Está guiado por los modelos y pantallas actuales en el repo (lib/models/doa_models.dart y lib/screens/admin/*) y por las tablas inferidas (users/user_profiles, restaurants, products, product_combos, product_combo_items, orders, order_items, payments, reviews, accounts, account_transactions, settlements, etc.).

 Si tu DATABASE_SCHEMA.sql difiere en nombres de columnas/tablas, ver “Dudas y confirmaciones” al final para ajustar antes de ejecutar SQL.

 ---

 ## 1) Objetivos
 - Operación end‑to‑end sin SQL manual: altas/bajas/cambios, aprobaciones, auditoría, reportes y analítica.
 - Escalabilidad: vistas/materialized views para KPIs y rendimiento con filtros.
 - Seguridad: RLS mantenido; mutaciones admin vía RPC security definer + auditoría completa.
 - UX moderna, rápida y usable para flujos de aprobación y monitoreo en tiempo real.

 ---

 ## 2) Módulos del Panel Admin

 1. Dashboard general (Home)
    - KPIs: Pedidos hoy, GMV hoy, comisiones hoy, restaurantes activos, repartidores online, pedidos pendientes.
    - Gráficas (línea/área): pedidos diarios/GMV últimos 30 días.
    - Alertas: “Restaurantes pendientes”, “Repartidores pendientes”, “Liquidaciones pendientes”.

 2. Restaurantes
    - Lista con filtros (estado, activo, tasa de rechazo, rating).
    - Checklist de publicación (nombre/desc/logo/cover/≥3 productos) con progreso.
    - Acciones: Aprobar / Rechazar / Reactivar / Suspender online.
    - Health: órdenes 30d, GMV 30d, rating promedio, cancelaciones, SLA (si está en esquema), ver reseñas.
    - Edición guiada: datos de negocio, horario, geolocalización, radio de entrega, imágenes (logo/portada/fachada/menú), unicidad nombre y teléfono.

 3. Menú: Productos y Combos
    - CRUD de productos, disponibilidad masiva, duplicar/clonar.
    - Editor de combos (product_combos + product_combo_items): añadir/quitar items con cantidades; validación 2..9 unidades.
    - Integridad: ver inconsistencias (productos borrados referenciados, precios anómalos).

 4. Pedidos
    - Monitor en tiempo real: filtros por estado, restaurante, repartidor, fecha.
    - Timeline del pedido: historial de status y eventos.
    - Acciones: reasignar repartidor, cancelar con motivo, reintentar notificaciones, emitir reembolsos (si aplica), marcar impago (RPC existente).
    - Exportación CSV/Excel de intervalos.

 5. Repartidores
    - Aprobación KYC: documentos, vehículo, verificación de email.
    - Estado: aprobar, rechazar, suspender, reactivar (RPC admin_update_delivery_agent_status).
    - Métricas: órdenes completadas, ganancias 30d, rating, cancelaciones, tiempo promedio.
    - Mapa live (si hay live_location_service), última ubicación.

 6. Usuarios (Clientes)
    - Lista con búsqueda/segmentos (activos, MAU/WAU, con impagos, alta recurrencia).
    - Perfil: LTV, pedidos, últimos tickets, reseñas hechas/recibidas, flags.

 7. Finanzas
    - Cuentas (accounts): balances y últimos movimientos.
    - Transacciones (account_transactions) por tipo: ORDER_REVENUE, PLATFORM_COMMISSION, DELIVERY_EARNING, etc.
    - Liquidaciones (settlements): flujo de aprobación/confirmación, conciliación “Balance 0”.
    - Reportes: GMV, Take rate, payouts a repartidores/restaurantes.

 8. Reseñas & Calidad
    - Moderación: listar reseñas, filtros por rating bajo, motivos.
    - Histogramas por restaurante/ repartidor; ver comentarios y tendencias.

 9. Configuración (parámetros de plataforma)
    - Tarifas base de delivery, matriz por distancia/tiempo (si aplica).
    - Comisión plataforma por restaurante/categoría.
    - Zonas de servicio.
    - Reglas de aprobación/umbral de checklist.
    - Textos del sistema (copys de notificaciones/ayudas).

 10. Auditoría (Audit Log)
    - Tabla audit_log con: actor_admin_id, acción, entidad, entidad_id, payload_before/after, timestamp.
    - Acciones registradas: cambios de estado en restaurantes/repartidores/pedidos, liquidaciones, config, reseñas moderadas.

 ---

 ## 3) Arquitectura y Seguridad
 - RLS se mantiene ON en tablas; los admins no bypassean RLS directamente.
 - Todas las mutaciones de admin pasan por RPCs con SECURITY DEFINER y checks de rol admin.
 - Vistas de solo lectura para analytics (CREATE OR REPLACE VIEW). Para cargas grandes: materialized views + función de refresh.
 - Realtime: canal para orders/status; panel refleja cambios live.
 - Auditoría obligatoria en triggers/RPCs.

 ---

 ## 4) Analytics: Vistas SQL propuestas (seguras y performantes)
 Archivo sugerido: supabase_scripts/2025-11-03_admin_analytics_views.sql

 - vw_admin_orders_daily: día, pedidos, entregados, cancelados, GMV (sum orders.total_amount).
 - vw_admin_restaurant_kpis_30d: por restaurante: pedidos 30d, GMV 30d, ticket promedio, rating promedio, cancelaciones 30d.
 - vw_admin_delivery_kpis_30d: por repartidor: completados 30d, cancelaciones 30d, ganancias 30d.
 - vw_admin_product_sales_30d: por producto: unidades y revenue 30d.
 - vw_finance_balances: snapshot de accounts con balance y última transacción.

 Estas vistas usan tablas observadas en el código: orders, order_items, products, restaurants, reviews, accounts, account_transactions, settlements. Ajusta nombres si tu schema usa user_profiles vs users, etc.

 ---

 ## 5) UX/UI Principios (según tu guía de diseño Material moderna)
 - Navegación: Rail lateral en desktop, NavigationBar en móvil; una sola jerarquía por pantalla.
 - Tablas profesionales: cabeceras pegajosas, filtros persistentes, búsqueda instantánea, paginación server‑side en datasets grandes.
 - Acciones masivas: aprobar/rechazar, activar/desactivar, exportar selección.
 - Badges/Chips: estado (pendiente/aprobado/rechazado), severidad, etiquetas de alerta.
 - Bottom sheets para confirmaciones críticas, con copy claro y consecuencias.
 - Visualización: sin sombras pesadas; chips/gradientes desde theme.dart; íconos con colores de alto contraste.
 - Accesibilidad: contraste suficiente, tamaños y espaciados, atajos básicos.

 ---

 ## 6) Roadmap de Implementación (fases)
 1. Fundaciones (DB + seguridad)
    - Crear vistas de analytics (archivo SQL adjunto) y función de refresh.
    - Definir audit_log y triggers/RPCs para registrar acciones admin.
    - Alinear RPCs existentes (e.g., admin_update_delivery_agent_status) y crear faltantes para cambios de estado en restaurantes, combos, pedidos, configuraciones.

 2. Dashboard y métricas
    - Conectar Dashboard a vistas vw_*; gráficos con fl_chart.
    - Alertas y contadores (pendientes por sección).

 3. Gestión profunda por entidad
    - Restaurantes: checklist + detalle + salud; aprobaciones.
    - Repartidores: KYC + estado + métricas.
    - Productos/Combos: CRUD completo + validador combos 2..9 + acciones masivas.
    - Pedidos: monitor live, timeline, acciones; exportador CSV.
    - Finanzas: cuentas, transacciones, liquidaciones.
    - Reseñas: moderación y analítica básica.

 4. Config + Auditoría
    - Pantalla de configuración centralizada (tarifas, comisiones, zonas).
    - Auditoría navegable por fecha/actor/entidad.

 5. Pulido y performance
    - Paginación server‑side; índices; materialized views si el volumen crece.
    - Tests de regresión visual y de RPCs.

 ---

 ## 7) Dudas y confirmaciones necesarias
 Por favor confirma o comparte el DATABASE_SCHEMA.sql para ajustar exactamente:
 1) users vs user_profiles: ¿Cuál es la tabla “fuente de verdad” para perfiles de usuario en admin?
 2) orders: columnas de tiempos (delivered_at, pickup_time, delivery_time) y source of truth para GMV (orders.total_amount vs sum(order_items.price_at_time_of_order*quantity)).
 3) reviews: nombres exactos (subject_restaurant_id, subject_user_id, rating, comment, created_at) y claves foráneas.
 4) financial: nombres exactos de accounts, account_transactions, settlements; enumeraciones de transaction.type.
 5) combos: product_combos y product_combo_items campos definitivos (updated_at en items sí/no) para integridad.
 6) ¿Tienes pg_cron o Supabase Scheduled Functions activas para refrescar materialized views (si las usamos)?

 ---

 ## 8) Sugerencias extra (escala y calidad)
 - Indexación proactiva: índices compuestos en orders(restaurant_id, created_at), order_items(product_id, created_at), reviews(subject_restaurant_id, created_at), account_transactions(account_id, created_at).
 - Soft‑deletes con deleted_at en entidades críticas.
 - Rate limiting en RPCs admin que afectan finanzas.
 - Export jobs asincrónicos (archivos CSV en storage) para intervalos grandes.
 - Notificaciones admin (correo/Slack) para colas de aprobación/alertas de riesgo.

 ---

 ## 9) FODA (SWOT)
 - Fortalezas
   - Modelo de datos ya cubre operación: pedidos, finanzas, reseñas, combos.
   - Código Flutter modular con servicios y pantallas admin base listas para extender.
   - Integración Supabase con RPCs clave y realtime.
 - Oportunidades
   - Consolidar analytics con vistas y materialized views.
   - Auditoría central para compliance y soporte.
   - Mejores flujos de aprobación y unicidad (nombre/teléfono de restaurantes).
   - Experiencia pro en tablas: filtros, exportación, acciones masivas.
 - Debilidades
   - Inconsistencia entre users y user_profiles en consultas actuales.
   - Reportes limitados y “Función en desarrollo” en varias secciones.
   - Falta de auditoría unificada y de vistas de desempeño por entidad.
 - Amenazas
   - Crecimiento de datos sin índices/materialized views puede degradar UX.
   - Cambios de esquema sin versionado rompen vistas/RPCs.
   - Riesgos de seguridad si mutaciones admin no pasan por security definer + auditoría.

 ---

 ## 10) Próximos pasos propuestos
 1) Validar/ajustar nombres exactos del schema (puntos 1–6 en “Dudas y confirmaciones”).
 2) Ejecutar/ajustar el SQL de vistas en supabase_scripts/2025-11-03_admin_analytics_views.sql.
 3) Conectar Dashboard a vw_admin_orders_daily y vw_admin_restaurant_kpis_30d con fl_chart.
 4) Extender las pantallas de gestión existentes para cubrir el roadmap (en sprints). 

 Si confirmas el schema, adapto el SQL al 100% y paso directo a implementar UI + wiring.
