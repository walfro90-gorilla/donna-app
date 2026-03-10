-- Agrega columna delivery_fee a la tabla restaurants.
-- Esta es la tarifa de entrega que se le muestra al cliente en la tarjeta
-- y se usa al crear órdenes. La plataforma cobra $35 como base.

ALTER TABLE restaurants
  ADD COLUMN IF NOT EXISTS delivery_fee double precision NOT NULL DEFAULT 35.0;

-- Todos los restaurantes existentes quedan con 35.0 por el DEFAULT del ALTER.
-- Si alguno hubiera quedado en 0 por alguna razón, normalizarlo:
UPDATE restaurants
SET delivery_fee = 35.0
WHERE delivery_fee = 0;
