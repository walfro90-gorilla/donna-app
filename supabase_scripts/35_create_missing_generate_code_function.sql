-- 🚨 CREAR LA FUNCIÓN FALTANTE: generate_random_code
-- Esta función es requerida por create_order_safe pero no existe

CREATE OR REPLACE FUNCTION generate_random_code(digits INTEGER)
RETURNS TEXT AS $$
BEGIN
    -- Generar código aleatorio con el número de dígitos especificado
    -- Para 3 dígitos: 000-999
    -- Para 4 dígitos: 0000-9999
    RETURN LPAD(FLOOR(RANDOM() * POWER(10, digits))::INTEGER::TEXT, digits, '0');
END;
$$ LANGUAGE plpgsql VOLATILE;