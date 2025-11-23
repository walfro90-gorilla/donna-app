# Migración: Ubicación en Tabla Users

## Descripción
Esta migración agrega campos de ubicación (lat, lon, address_structured) a la tabla `users` para almacenar la ubicación de todos los usuarios (clientes, repartidores, restaurantes).

## Cambios Aplicados

### 1. Nuevos Campos en `users`
- `lat` (DOUBLE PRECISION): Latitud (-90 a 90)
- `lon` (DOUBLE PRECISION): Longitud (-180 a 180)
- `address_structured` (JSONB): Dirección estructurada de Google Maps

### 2. Constraints
- CHECK constraints para validar rangos de lat/lon
- Campos nullable (opcionales)

### 3. Índices
- Índice compuesto en (lat, lon) para búsquedas geoespaciales eficientes

### 4. Migración de Datos Existentes
- Copia automática de `location_lat`, `location_lon`, `address_structured` desde tabla `restaurants` hacia `users` para usuarios con role='restaurante'

## Instrucciones de Despliegue

### Opción A: Desde Supabase Dashboard (Recomendado)
1. Abre Supabase Dashboard: https://supabase.com/dashboard
2. Selecciona tu proyecto
3. Ve a SQL Editor
4. Copia y pega el contenido de `001_add_location_to_users.sql`
5. Ejecuta el script
6. Verifica que se ejecutó correctamente revisando los logs

### Opción B: Desde CLI Local (Si descargaste el código)
```bash
# Navega al directorio del proyecto
cd /path/to/doa_repartos

# Ejecuta la migración usando Supabase CLI
supabase migration new add_location_to_users
supabase db push
```

## Validación Post-Migración

Ejecuta estas queries en SQL Editor para verificar:

```sql
-- 1. Verificar que las columnas existen
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'users' 
  AND column_name IN ('lat', 'lon', 'address_structured');

-- 2. Verificar usuarios con ubicación
SELECT 
  role,
  COUNT(*) as total,
  COUNT(lat) as with_location,
  ROUND(100.0 * COUNT(lat) / COUNT(*), 2) as percentage
FROM users
GROUP BY role;

-- 3. Verificar que los índices fueron creados
SELECT indexname, indexdef 
FROM pg_indexes 
WHERE tablename = 'users' 
  AND indexname = 'idx_users_location';
```

## Rollback (En caso de error)

Si necesitas revertir la migración:

```sql
-- Remover índice
DROP INDEX IF EXISTS public.idx_users_location;

-- Remover columnas
ALTER TABLE public.users
  DROP COLUMN IF EXISTS lat,
  DROP COLUMN IF EXISTS lon,
  DROP COLUMN IF EXISTS address_structured;
```

## Notas Importantes

1. **Compatibilidad Backward**: Los campos son nullable, por lo que usuarios existentes sin ubicación seguirán funcionando
2. **Performance**: El índice geoespacial mejora significativamente las búsquedas por ubicación
3. **Duplicación de Datos**: Tabla `restaurants` mantiene sus campos `location_*` para flexibilidad (dueño puede vivir en otra dirección que su restaurante)

## Testing

Después de aplicar la migración, prueba:

1. **Registro de nuevo repartidor** → Debe guardar lat/lon en users
2. **Registro de nuevo restaurante** → Debe guardar ubicación en users Y restaurants
3. **Editar perfil de restaurante** → Debe actualizar ubicación
4. **Búsqueda geoespacial** → Query de ejemplo:

```sql
-- Buscar usuarios cerca de una coordenada (10km radius)
SELECT id, name, lat, lon
FROM users
WHERE lat IS NOT NULL 
  AND lon IS NOT NULL
  AND ST_DWithin(
    ST_MakePoint(lon, lat)::geography,
    ST_MakePoint(-106.454386, 31.650235)::geography,
    10000  -- 10km en metros
  );
```

## Contacto y Soporte

Si encuentras problemas durante la migración:
- Revisa los logs de Supabase
- Verifica que tienes permisos de Admin en el proyecto
- Contacta al equipo de desarrollo
