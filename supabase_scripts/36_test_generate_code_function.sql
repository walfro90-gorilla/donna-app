-- 🧪 TEST: Probar la función generate_random_code
-- Verificar que genere códigos correctos

-- Test 1: Generar códigos de 3 dígitos
SELECT 
    'Test 3 dígitos' AS test,
    generate_random_code(3) AS code_1,
    generate_random_code(3) AS code_2,
    generate_random_code(3) AS code_3;

-- Test 2: Generar códigos de 4 dígitos  
SELECT 
    'Test 4 dígitos' AS test,
    generate_random_code(4) AS code_1,
    generate_random_code(4) AS code_2,
    generate_random_code(4) AS code_3;

-- Test 3: Verificar longitud correcta
SELECT 
    'Test longitud' AS test,
    LENGTH(generate_random_code(3)) AS len_3_digits,
    LENGTH(generate_random_code(4)) AS len_4_digits;