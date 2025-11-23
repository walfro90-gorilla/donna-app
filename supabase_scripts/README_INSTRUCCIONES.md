# 📋 INSTRUCCIONES PASO A PASO - SCRIPTS SUPABASE

## 🚀 **ORDEN DE EJECUCIÓN**

Ejecuta estos scripts **EN ORDEN** en el SQL Editor de Supabase:

### **PASO 1:** Ejecutar `01_create_order_function.sql`
```sql
-- Crea la función RPC create_order_safe()
-- Esta función evita los triggers problemáticos al crear órdenes
```

### **PASO 2:** Ejecutar `02_create_order_items_function.sql`  
```sql
-- Crea la función RPC insert_order_items()
-- Esta función inserta los productos de la orden
```

### **PASO 3:** (OPCIONAL) Ejecutar `03_disable_problematic_triggers.sql`
```sql
-- Solo si sigues teniendo problemas con triggers
-- Primero ejecuta la consulta SELECT para ver qué triggers tienes
```

### **PASO 4:** Ejecutar `04_verify_tables.sql`
```sql
-- Verifica que tus tablas tengan la estructura correcta
-- Revisa que las columnas coincidan con lo que espera el código
```

### **PASO 5:** Ejecutar `05_test_functions.sql`
```sql
-- Prueba las funciones creadas
-- IMPORTANTE: Reemplaza los UUIDs con valores reales de tu DB
```

---

## 🔧 **DESPUÉS DE EJECUTAR LOS SCRIPTS**

Una vez ejecutados los scripts 1 y 2 exitosamente:

1. **Las funciones RPC estarán disponibles** en tu base de datos
2. **El código Flutter las usará automáticamente** 
3. **Prueba crear una orden** desde la app

---

## ⚠️ **TROUBLESHOOTING**

- **Error 404 en RPC:** Las funciones no se crearon correctamente, re-ejecutar scripts 1 y 2
- **Error de permisos:** Verificar que las líneas GRANT se ejecutaron  
- **Error de triggers:** Ejecutar script 3 para investigar triggers problemáticos
- **Error de columnas:** Ejecutar script 4 para verificar estructura de tablas

---

## 📞 **CONTACTO**

Si necesitas ayuda después de ejecutar los scripts, comparte:
1. ✅ Qué scripts ejecutaste exitosamente
2. ❌ Qué errores obtuviste (con mensaje completo)
3. 📋 Resultado del script 4 (verificación de tablas)