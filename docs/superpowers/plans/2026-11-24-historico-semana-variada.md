# Semana operativa de prueba: 17–23 noviembre 2026

1. Inspeccionar local y Railway sin escribir: cobros, jornadas, cierres, conteos y pedidos pendientes.
2. Crear un cargador separado, determinista y transaccional, con modo plan por defecto.
3. Generar tickets variados según sede/día, efectivo/tarjeta y tipos de comprobante internos;
   consumir recetas existentes, sin modificar ingredientes ni invocar facturación externa.
4. Distribuir recepciones por proveedor los días 17, 20 y 23; incluir importes e IGV calculados
   con el servicio existente. Registrar mermas pequeñas y conteos con trazabilidad.
5. Reconstruir aperturas y cierres de la semana por movimientos cronológicos. Corregir solo
   vínculos derivados de jornada cuando la fecha del cobro/evento no coincide. No alterar
   importes, líneas, clientes ni métodos de operaciones manuales.
6. Actualizar únicamente cierres simulados; no sobrescribir cierres operativos confirmados.
   Detenerse ante pedidos sin cobrar o conteos abiertos. Mantener intactas fechas posteriores.
7. Probar consistencia, variedad, repetición sin duplicados y ausencia de trabajos fact_api.
   Ejecutar en transacción local y online, verificar resultados. Respaldar y publicar cambios.
