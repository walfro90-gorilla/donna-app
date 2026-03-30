---
name: blueprint_extras_mobile
description: Blueprint completo de extras (modifier groups) para la app móvil — arquitectura M:M, schema, queries correctas, shape de datos esperado
type: project
---

# Blueprint: Extras / Modifier Groups — App Móvil

**Fecha:** 2026-03-29
**Audiencia:** Equipo de app móvil (Flutter/React Native/Expo)
**Por qué:** El sistema de extras de productos migró de 1:1 a Many-to-Many. La app móvil debe actualizar sus queries para leer la nueva estructura.

---

## TL;DR — Cambio crítico

| Antes | Después |
|---|---|
| `modifier_groups.product_id` era la FK principal | `product_modifier_groups` es la join table |
| `SELECT * FROM modifier_groups WHERE product_id = $id` | `SELECT ... FROM product_modifier_groups WHERE product_id = $id` |
| Un grupo solo pertenecía a 1 producto | Un grupo puede reutilizarse en N productos del mismo restaurante |

> ⚠️ **No filtrar por `modifier_groups.product_id`** — ese campo es nullable y NO se actualiza para grupos nuevos. Solo existe por compatibilidad con datos históricos.

---

## Schema actual (verificado 2026-03-29)

### `modifier_groups`

```sql
id            uuid      PK, default uuid_generate_v4()
restaurant_id uuid      NOT NULL → restaurants.id ON DELETE CASCADE  ← NUEVO
product_id    uuid      NULLABLE → products.id ON DELETE CASCADE      ← LEGACY, no usar
name          text      NOT NULL
description   text      NULLABLE
selection_type text     NOT NULL, default 'single'  -- 'single' | 'multiple'
min_selections integer  NOT NULL, default 0
max_selections integer  NOT NULL, default 1
is_required   boolean   NOT NULL, default false
sort_order    integer   NOT NULL, default 0
is_active     boolean   NOT NULL, default true
created_at    timestamptz
updated_at    timestamptz
```

### `product_modifier_groups` (join table — nueva)

```sql
product_id        uuid  NOT NULL → products.id ON DELETE CASCADE
modifier_group_id uuid  NOT NULL → modifier_groups.id ON DELETE CASCADE
sort_order        integer NOT NULL, default 0
created_at        timestamptz
PRIMARY KEY (product_id, modifier_group_id)
```

### `modifiers` (sin cambios)

```sql
id          uuid    PK
group_id    uuid    NOT NULL → modifier_groups.id ON DELETE CASCADE
name        text    NOT NULL
description text    NULLABLE
price_delta float8  NOT NULL, default 0.0   -- precio adicional en MXN
is_available boolean NOT NULL, default true
sort_order  integer NOT NULL, default 0
created_at  timestamptz
updated_at  timestamptz
```

### `products` (referencia)

```sql
id            uuid    PK
restaurant_id uuid    NOT NULL
name          text    NOT NULL
description   text    NULLABLE
price         numeric NOT NULL   -- precio PLATAFORMA (con comisión incluida)
image_url     text    NULLABLE
is_available  boolean default true
type          enum    'principal' | 'bebida' | 'postre' | 'entrada' | 'combo'
contains      jsonb   NULLABLE
```

---

## Relación de tablas (diagrama)

```
restaurants
    │
    ├── products (restaurant_id)
    │       │
    │       └── product_modifier_groups (product_id) ──── modifier_groups (modifier_group_id)
    │                                                             │
    │                                                             └── modifiers (group_id)
    │
    └── modifier_groups (restaurant_id)   ← un grupo pertenece al restaurante,
                                             no a un producto específico
```

---

## Queries correctas para la app móvil

### 1. Cargar menú completo de un restaurante con extras

```sql
-- SQL puro
SELECT
  p.id,
  p.name,
  p.description,
  p.price,
  p.image_url,
  p.is_available,
  p.type,
  mg.id          AS group_id,
  mg.name        AS group_name,
  mg.selection_type,
  mg.min_selections,
  mg.max_selections,
  mg.is_required,
  pmg.sort_order AS group_sort_order,
  m.id           AS modifier_id,
  m.name         AS modifier_name,
  m.price_delta,
  m.is_available AS modifier_available,
  m.sort_order   AS modifier_sort_order
FROM products p
LEFT JOIN product_modifier_groups pmg ON pmg.product_id = p.id
LEFT JOIN modifier_groups mg ON mg.id = pmg.modifier_group_id AND mg.is_active = true
LEFT JOIN modifiers m ON m.group_id = mg.id AND m.is_available = true
WHERE p.restaurant_id = $restaurant_id
  AND p.is_available = true
ORDER BY p.name, pmg.sort_order, m.sort_order;
```

### 2. Cargar extras de UN producto (al abrir modal de personalización)

```sql
-- SQL puro
SELECT
  mg.id,
  mg.name,
  mg.selection_type,
  mg.min_selections,
  mg.max_selections,
  mg.is_required,
  pmg.sort_order,
  json_agg(
    json_build_object(
      'id', m.id,
      'name', m.name,
      'price_delta', m.price_delta,
      'is_available', m.is_available,
      'sort_order', m.sort_order
    ) ORDER BY m.sort_order
  ) AS modifiers
FROM product_modifier_groups pmg
JOIN modifier_groups mg ON mg.id = pmg.modifier_group_id
LEFT JOIN modifiers m ON m.group_id = mg.id AND m.is_available = true
WHERE pmg.product_id = $product_id
  AND mg.is_active = true
GROUP BY mg.id, mg.name, mg.selection_type, mg.min_selections, mg.max_selections, mg.is_required, pmg.sort_order
ORDER BY pmg.sort_order;
```

### 3. Detectar si productos tienen extras (para mostrar badge/ícono)

```sql
-- Obtener los product_ids que tienen al menos 1 grupo activo
SELECT DISTINCT pmg.product_id
FROM product_modifier_groups pmg
JOIN modifier_groups mg ON mg.id = pmg.modifier_group_id AND mg.is_active = true
WHERE pmg.product_id IN ($id1, $id2, $id3, ...);
```

---

## Queries con Supabase SDK (JavaScript/TypeScript)

### Cargar extras de un producto

```typescript
const { data, error } = await supabase
  .from('product_modifier_groups')
  .select(`
    sort_order,
    modifier_groups!inner (
      id,
      name,
      selection_type,
      min_selections,
      max_selections,
      is_required,
      modifiers (
        id,
        name,
        price_delta,
        is_available,
        sort_order
      )
    )
  `)
  .eq('product_id', productId)
  .eq('modifier_groups.is_active', true)
  .order('sort_order');

// Normalizar al shape que usa la app
const groups = (data ?? [])
  .sort((a, b) => a.sort_order - b.sort_order)
  .map(row => ({
    ...row.modifier_groups,
    modifiers: (row.modifier_groups.modifiers ?? [])
      .filter(m => m.is_available)
      .sort((a, b) => a.sort_order - b.sort_order),
  }));
```

### Detectar extras para lista de productos

```typescript
const { data } = await supabase
  .from('product_modifier_groups')
  .select('product_id')
  .in('product_id', productIds);

const productsWithExtras = new Set(data?.map(r => r.product_id) ?? []);
```

---

## Shape de datos esperado (modelo para la app)

```typescript
interface Modifier {
  id: string;
  name: string;
  price_delta: number;   // 0 = sin costo adicional
  is_available: boolean;
  sort_order: number;
}

interface ModifierGroup {
  id: string;
  name: string;
  selection_type: 'single' | 'multiple';
  min_selections: number;  // 0 = opcional
  max_selections: number;  // 1 si single, N si multiple
  is_required: boolean;    // true si min_selections > 0
  modifiers: Modifier[];
}

interface Product {
  id: string;
  name: string;
  description: string | null;
  price: number;           // precio al cliente (plataforma, con comisión)
  image_url: string | null;
  is_available: boolean;
  type: 'principal' | 'bebida' | 'postre' | 'entrada' | 'combo';
  modifier_groups: ModifierGroup[];   // [] si no tiene extras
}
```

---

## Lógica de validación al ordenar (UI)

Antes de permitir que el usuario agregue el producto al carrito, validar:

```typescript
function validateExtras(groups: ModifierGroup[], selections: Record<string, string[]>): string | null {
  for (const group of groups) {
    const chosen = selections[group.id] ?? [];

    if (group.selection_type === 'single' && group.is_required && chosen.length === 0) {
      return `Debes elegir una opción en "${group.name}"`;
    }

    if (group.selection_type === 'multiple') {
      if (chosen.length < group.min_selections) {
        return `Elige al menos ${group.min_selections} opciones en "${group.name}"`;
      }
      if (chosen.length > group.max_selections) {
        return `Máximo ${group.max_selections} opciones en "${group.name}"`;
      }
    }
  }
  return null; // válido
}
```

---

## Reglas de negocio

| Campo | Regla |
|---|---|
| `selection_type = 'single'` | Radio buttons — solo 1 opción, `max_selections = 1` |
| `selection_type = 'multiple'` | Checkboxes — entre `min_selections` y `max_selections` |
| `min_selections = 0` | El grupo es **opcional** |
| `min_selections > 0` | El grupo es **obligatorio** (mismo efecto que `is_required = true`) |
| `price_delta = 0` | Opción sin costo adicional |
| `price_delta > 0` | Se suma al precio base del producto |

---

## ❌ Queries que ya NO funcionan para grupos nuevos

```typescript
// ❌ MAL — product_id no se actualiza para grupos nuevos
const { data } = await supabase
  .from('modifier_groups')
  .select('*, modifiers(*)')
  .eq('product_id', productId);

// ❌ MAL — mismo error en SQL
SELECT * FROM modifier_groups WHERE product_id = $productId;
```

> Los datos históricos (antes de la migración) sí tienen `product_id` relleno, pero los grupos creados desde el admin desde 2026-03 en adelante solo tienen la relación en `product_modifier_groups`.

---

## Resumen de migración aplicada en BD

1. Se agregó `restaurant_id NOT NULL` a `modifier_groups`
2. Se creó `product_modifier_groups` (join table)
3. Se migró data existente: cada grupo copiado a `product_modifier_groups`
4. Se hizo backfill de `modifier_groups.restaurant_id` para datos históricos
5. `modifier_groups.product_id` quedó nullable (legacy, no usar)

**Migración aplicada:** `modifier_groups_many_to_many` + `backfill_modifier_groups_product_id`
