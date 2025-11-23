# 🚀 REFACTOR 2025 - GUÍA DE EJECUCIÓN

## 📋 DESCRIPCIÓN

Scripts SQL para refactorizar el sistema de registro de usuarios en Doa Repartos.
Simplifica tablas, elimina código obsoleto y crea 3 RPCs profesionales y atómicos.

---

## ⚠️ ANTES DE EMPEZAR

### Prerrequisitos
- [ ] Acceso al SQL Editor de Supabase
- [ ] Permisos de administrador en la base de datos
- [ ] Backup manual de la base de datos (opcional, pero recomendado)
- [ ] Ambiente de staging para testing (muy recomendado)

### Tiempo Estimado Total
**90 minutos** (incluyendo testing y verificación)

### Downtime Esperado
**30-60 minutos** durante las fases 2-5

---

## 📁 ARCHIVOS EN ORDEN DE EJECUCIÓN

| # | Archivo | Descripción | Tiempo | Crítico |
|---|---------|-------------|--------|---------|
| 1 | `01_backup_current_state.sql` | Backup completo | 5 min | ⚠️ Obligatorio |
| 2 | `02_cleanup_obsolete_functions.sql` | Elimina RPCs legacy | 5 min | ✅ Seguro |
| 3 | `03_cleanup_triggers.sql` | Elimina triggers conflictivos | 2 min | ⚠️ Crítico |
| 4 | `04_migrate_data.sql` | Migra datos a nuevas ubicaciones | 10 min | ⚠️ Crítico |
| 5 | `05_alter_tables.sql` | Elimina columnas obsoletas | 10 min | 🚨 Punto de no retorno |
| 6 | `06_create_register_client.sql` | RPC registro cliente | 5 min | ✅ Seguro |
| 7 | `07_create_register_restaurant.sql` | RPC registro restaurante | 5 min | ✅ Seguro |
| 8 | `08_create_register_delivery_agent.sql` | RPC registro repartidor | 5 min | ✅ Seguro |
| 9 | `09_update_rls_policies.sql` | Actualiza políticas RLS | 10 min | ⚠️ Crítico |
| 10 | `10_test_registrations.sql` | Tests completos | 15 min | ✅ Verificación |
| 11 | `11_create_indexes.sql` | Índices optimizados | 5 min | ✅ Performance |

---

## 🔄 PROCESO DE EJECUCIÓN

### OPCIÓN A: Ejecución Manual (Recomendada para producción)

1. **Abrir SQL Editor en Supabase**
   - Ir a: Project > SQL Editor
   - Crear nuevo query

2. **Ejecutar cada archivo EN ORDEN**
   ```sql
   -- Copiar contenido de 01_backup_current_state.sql
   -- Pegar en SQL Editor
   -- Click en "Run" o Ctrl+Enter
   -- Verificar resultados
   -- Proceder al siguiente archivo
   ```

3. **Verificar después de cada fase**
   - Leer los comentarios de verificación al final de cada script
   - Si algo falla, NO continuar
   - Revisar logs en `debug_logs` table

### OPCIÓN B: Ejecución por Bloques (Para staging)

```sql
-- Ejecutar archivos 1-3 juntos (Preparación y limpieza)
\i 01_backup_current_state.sql
\i 02_cleanup_obsolete_functions.sql
\i 03_cleanup_triggers.sql

-- ⚠️ CHECKPOINT 1: Verificar que no hay errores

-- Ejecutar archivos 4-5 juntos (Migración y alteración)
\i 04_migrate_data.sql
\i 05_alter_tables.sql

-- ⚠️ CHECKPOINT 2: Punto crítico - verificar integridad

-- Ejecutar archivos 6-8 juntos (Nuevos RPCs)
\i 06_create_register_client.sql
\i 07_create_register_restaurant.sql
\i 08_create_register_delivery_agent.sql

-- Ejecutar archivos 9-11 juntos (RLS, tests y optimización)
\i 09_update_rls_policies.sql
\i 10_test_registrations.sql
\i 11_create_indexes.sql
```

---

## ✅ CHECKPOINTS DE VERIFICACIÓN

### Después de FASE 1 (Backup)
```sql
-- Ver conteo de backups
SELECT 
  'users_backup' AS tabla,
  COUNT(*) AS registros
FROM backup_refactor_2025.users_backup
UNION ALL
SELECT 'client_profiles_backup', COUNT(*) 
FROM backup_refactor_2025.client_profiles_backup;

-- ✅ Debe retornar el conteo actual de tus tablas
```

### Después de FASE 4 (Migración)
```sql
-- Ver usuarios sin perfil
SELECT * FROM validation_report WHERE NOT has_profile;

-- ✅ NO debe retornar resultados
-- ⚠️ Si retorna resultados, corregir antes de continuar
```

### Después de FASE 5 (Alteración)
```sql
-- Ver estructura de users
SELECT column_name FROM information_schema.columns
WHERE table_name = 'users' AND table_schema = 'public'
ORDER BY ordinal_position;

-- ✅ Debe mostrar exactamente 8 columnas:
-- id, email, name, phone, role, email_confirm, created_at, updated_at
```

### Después de FASE 7 (Tests)
```sql
-- Ver resumen de tests
SELECT * FROM (
  SELECT 
    (SELECT COUNT(*) FROM users WHERE email LIKE '%refactor@example.com') AS usuarios,
    (SELECT COUNT(*) FROM client_profiles cp JOIN users u ON cp.user_id = u.id 
     WHERE u.email LIKE '%refactor@example.com') AS clientes,
    (SELECT COUNT(*) FROM restaurants r JOIN users u ON r.user_id = u.id 
     WHERE u.email LIKE '%refactor@example.com') AS restaurantes,
    (SELECT COUNT(*) FROM delivery_agent_profiles dp JOIN users u ON dp.user_id = u.id 
     WHERE u.email LIKE '%refactor@example.com') AS repartidores
) tests;

-- ✅ Debe retornar: usuarios=3, clientes=1, restaurantes=1, repartidores=1
```

---

## 🚨 ROLLBACK

### Si necesitas revertir (ANTES de FASE 5)

```sql
-- Restaurar desde backup
BEGIN;

-- Restaurar users
TRUNCATE public.users CASCADE;
INSERT INTO public.users 
SELECT * FROM backup_refactor_2025.users_backup;

-- Restaurar client_profiles
TRUNCATE public.client_profiles CASCADE;
INSERT INTO public.client_profiles 
SELECT * FROM backup_refactor_2025.client_profiles_backup;

-- Restaurar restaurants
TRUNCATE public.restaurants CASCADE;
INSERT INTO public.restaurants 
SELECT * FROM backup_refactor_2025.restaurants_backup;

-- Restaurar delivery_agent_profiles
TRUNCATE public.delivery_agent_profiles CASCADE;
INSERT INTO public.delivery_agent_profiles 
SELECT * FROM backup_refactor_2025.delivery_agent_profiles_backup;

COMMIT;
```

### Si necesitas revertir (DESPUÉS de FASE 5)

⚠️ **MUY DIFÍCIL** - Requiere restaurar backup completo de la base de datos.

---

## 📊 MONITOREO POST-DEPLOYMENT

### Queries de monitoreo

```sql
-- Ver logs de registro (últimas 24 horas)
SELECT 
  scope,
  message,
  meta->>'email' AS email,
  meta->>'user_id' AS user_id,
  ts
FROM debug_logs
WHERE scope LIKE 'REGISTER_%'
  AND ts > NOW() - INTERVAL '24 hours'
ORDER BY ts DESC;

-- Ver tasa de éxito
SELECT 
  scope,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE scope LIKE '%SUCCESS%') AS exitosos,
  COUNT(*) FILTER (WHERE scope LIKE '%ERROR%') AS errores
FROM debug_logs
WHERE scope LIKE 'REGISTER_%'
  AND ts > NOW() - INTERVAL '24 hours'
GROUP BY scope;

-- Ver usuarios registrados hoy
SELECT 
  role,
  COUNT(*) AS registros_hoy
FROM users
WHERE DATE(created_at) = CURRENT_DATE
GROUP BY role;
```

---

## 🔧 TROUBLESHOOTING

### Error: "Email already exists"
- Normal en tests
- Limpiar datos de test con `10_test_registrations.sql`

### Error: "Function does not exist"
- Verificar que FASE 6-8 se ejecutaron correctamente
- Revisar permisos: `GRANT EXECUTE ON FUNCTION...`

### Error: "Column does not exist"
- Probablemente saltaste FASE 4 (migración)
- Revisar que `04_migrate_data.sql` se ejecutó completo

### Performance lenta después de refactor
- Ejecutar `11_create_indexes.sql` si no se hizo
- Ejecutar `ANALYZE` en las tablas principales

---

## 📞 CONTACTO

**Documentación:** `/docs/MASTER_PLAN_REFACTOR_2025.md`
**Logs:** `public.debug_logs` table
**Support:** [Tu email o canal de soporte]

---

## ✅ CHECKLIST FINAL

Después de completar todas las fases:

- [ ] Todos los scripts ejecutados sin errores
- [ ] Tests pasando (FASE 7)
- [ ] Logs de debug sin errores críticos
- [ ] App Flutter actualizada para usar nuevos RPCs
- [ ] Tests end-to-end en app funcionando
- [ ] Monitoreo activo por 24-48 horas
- [ ] Documentación actualizada
- [ ] Equipo notificado de los cambios

---

**Versión:** 1.0
**Fecha:** 2025-01-XX
**Autor:** [Tu nombre]
