# Reutilizar documentos y plantillas originales de fact_api

Alcance autorizado: crear boletas/facturas de demostración mediante DocumentService,
usar PdfService y las plantillas originales A4/80 mm, conservar idempotencia,
cola, permisos y archivos privados. No enviar a SUNAT.

Las compras conservan la OC, recepción y factura original del proveedor; su PDF
generado es una representación interna, nunca una emisión a nombre del proveedor.

Pasos y comprobaciones:
1. Pruebas HTTP: servicios nativos, importes con IGV incluido, reintentos sin duplicar.
2. Adaptar creación y renderizado; continuar correlativos existentes.
3. Verificar ambos formatos, originales de compras y aislamiento de clientes.
4. Medir POST, primer PDF y PDF ya generado por separado en el servicio local real.
5. Documentar recorrido, tiempos medidos y límites de la prueba.
