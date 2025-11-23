# ⚡ GUÍA RÁPIDA DE EJECUCIÓN

## 🎯 Para ejecutar en producción HOY

### 1️⃣ BACKUP (OBLIGATORIO)
```sql
-- Abrir: 01_backup_current_state.sql
-- Copiar TODO el contenido
-- Pegar en Supabase SQL Editor
-- RUN
-- ✅ Verificar que veas conteos de registros al final
```

### 2️⃣ LIMPIEZA (5 minutos)
```sql
-- Ejecutar EN ORDEN:
-- 02_cleanup_obsolete_functions.sql
-- 03_cleanup_triggers.sql
-- ✅ Sin errores = continúa
```

### 3️⃣ MIGRACIÓN (15 minutos) ⚠️ CRÍTICO
```sql
-- Ejecutar EN ORDEN:
-- 04_migrate_data.sql
-- ⚠️ VERIFICAR: No debe haber usuarios sin perfil
-- 05_alter_tables.sql
-- ⚠️ PUNTO DE NO RETORNO - Verifica 8 columnas en users
```

### 4️⃣ NUEVOS RPCs (15 minutos)
```sql
-- Ejecutar EN ORDEN:
-- 06_create_register_client.sql
-- 07_create_register_restaurant.sql
-- 08_create_register_delivery_agent.sql
-- ✅ Estos son seguros
```

### 5️⃣ FINALIZACIÓN (30 minutos)
```sql
-- Ejecutar EN ORDEN:
-- 09_update_rls_policies.sql
-- 10_test_registrations.sql (⚠️ VER RESULTADOS)
-- 11_create_indexes.sql
-- ✅ LISTO!
```

---

## 📊 VERIFICACIÓN RÁPIDA

Después de TODO:

```sql
-- ¿Funciona el registro?
SELECT public.register_client(
  'test@example.com',
  'password123',
  'Test User',
  '+1234567890'
);

-- ✅ Debe retornar JSON con success: true
```

---

## 🚨 SI ALGO FALLA

```sql
-- Ver últimos errores
SELECT * FROM debug_logs 
WHERE scope LIKE '%ERROR%' 
ORDER BY ts DESC 
LIMIT 10;
```

### Rollback (solo ANTES de archivo 05)
```sql
-- Restaurar desde backup
INSERT INTO public.users 
SELECT * FROM backup_refactor_2025.users_backup;
-- (y así para todas las tablas)
```

---

## 📞 ¿NECESITAS AYUDA?

1. Lee el `README.md` completo
2. Lee el `MASTER_PLAN_REFACTOR_2025.md` en `/docs`
3. Revisa `debug_logs` table
4. Contacta al equipo de desarrollo

---

## ⏱️ TIMING

- **Total:** 90 minutos
- **Downtime:** 30-60 min (fases 2-5)
- **Best time:** Fuera de horario pico

---

## ✅ DONE?

- [ ] Backup hecho
- [ ] Todos los scripts ejecutados
- [ ] Tests pasando
- [ ] App actualizada
- [ ] Monitoreo activo

🎉 **¡Felicidades!** Sistema refactorizado exitosamente.
