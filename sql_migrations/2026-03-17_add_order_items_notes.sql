-- Add per-item notes field to order_items
-- Allows clients to add special instructions per item (e.g., sauce selection for boneless)
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS notes text;
