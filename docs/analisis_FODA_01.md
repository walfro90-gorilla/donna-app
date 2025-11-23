# Análisis FODA (SWOT) — Plataforma tipo DoorDash

Fecha: 2025-10-19

Fortalezas
- Arquitectura modular por roles (cliente, restaurante, repartidor, admin) con dashboards dedicados.
- Supabase con RLS, RPCs y triggers para procesos críticos (registros, perfiles, cuentas, balance cero).
- Sistema de contabilidad “Balance 0” establecido con cuentas de plataforma y transacciones pareadas.
- Servicios clave: localización en vivo, pedidos, liquidaciones, reseñas, notificaciones.

Oportunidades
- Automatizar onboarding de todos los roles (ya aplicado para restaurant/delivery_agent; ahora clientes).
- Mejorar UX responsive y estados vacíos/loaders; optimizar consultas con índices.
- Unificar nomenclaturas de roles y tipos (ES/EN) con normalizadores.
- Observabilidad: métricas de negocio (LTV, AOV, cancel rate) y alertas técnicas.

Debilidades
- Discrepancias históricas de roles (cliente vs client vs cliente) causaban desvíos de navegación.
- Falta de perfil/ cuenta financiera para clientes impedía manejar deuda y scoring.
- Dependencias de front-end en pasos sensibles (p.ej. creación de perfiles) sin respaldo de triggers.

Amenazas
- RLS estrictas pueden bloquear flujos si no existen funciones SECURITY DEFINER de soporte.
- Riesgo contable si no se respetan asientos dobles en todos los casos (reembolsos, anulaciones).
- Latencias del tiempo real o geolocalización pueden afectar la experiencia de tracking.

Prioridades próximas (90 días)
1) Onboarding automático de clientes (client_profiles + accounts) con trigger/función segura.
2) Fortalecer “Balance 0” para escenarios de deuda, reembolsos y cancelaciones.
3) Normalizar roles/tipos y endurecer validaciones (lint/CI de SQL y tests de RPCs).
4) Optimización de consultas de dashboards (índices + RPCs agregadas cuando RLS limita joins).
5) Observabilidad de negocio y técnica (logs estructurados, paneles de métricas e incidentes).

KPIs sugeridos
- t_create_profile: < 200ms p95; tasa de error < 0.5%.
- t_first_paint_dashboard: < 1.5s web móvil p75.
- Balance total sistema: = 0.00 siempre; desviación 0.
- Conversión onboarding por rol: > 95% de éxito sin intervención manual.

Riesgos y mitigación
- Triggers en esquema auth: usar fallback en public.users si no se permite.
- RLS bloqueando flujos: siempre ofrecer RPC SECURITY DEFINER y políticas owner.
- Migraciones peligrosas: DO blocks idempotentes, backfill controlado y tests de verificación.
