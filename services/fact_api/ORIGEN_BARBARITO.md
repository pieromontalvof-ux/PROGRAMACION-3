# fact_api integrado en Barbarito

Fuente: https://github.com/angelitosystems/fact_api (rama main, descargada 2026-11-21).
Se conserva el README y composer.lock original. No es un servicio oficial de SUNAT.

Ampliación local: rutas `api/barbarito`, configuración `barbarito.php`, controlador
`BarbaritoController`, migración `2026_11_21`, `BarbaritoPdfService` y plantilla.
Reutiliza Laravel y modelos Company/Branch/Client/Invoice/Boleta. Desde el ajuste
de plantillas nativas, las ventas pasan por DocumentService::createInvoice /
createBoleta y PdfService::generateInvoicePdf / generateBoletaPdf con las
plantillas originales A4 y 80mm. BarbaritoPdfService y su plantilla quedan para
representaciones internas de compras, nunca para emitir facturas del proveedor.

Adaptaciones al servicio original: clientes separados por empresa (con migración
de unicidad), precios que ya incluyen IGV y validación contra el cobro original.
El puente continúa los correlativos existentes; no reinicia series. Las plantillas
usan el logo de Barbarian y el mismo número completo en ambos formatos. En DEMO
omiten QR, CDR y afirmaciones de autorización/verificación; conservan el aviso de
falta de validez tributaria. Dompdf no puede ejecutar PHP ni descargar recursos.
Dos migraciones upstream se ajustaron para PostgreSQL: el ENUM MySQL se convirtió
en CHECK y se evita volver a agregar columnas que ya existen. Los cambios están
en 2025_09_13_140000 y 2025_12_15_104136.

Con BARBARITO_DEMO_ONLY=true solo se publican las rutas del puente; las rutas
upstream de setup y envío SUNAT no están accesibles. No se produce XML firmado
ni CDR ficticio. Compras se conservan separadas en barbarito_documents y no se
registran como ventas. Sus PDF son vistas internas, no originales del proveedor.

Los PDF se guardan en el disco privado local. Barbarito conserva una copia de
entrega con SHA-256 para servirla aplicando sus permisos por local. Ambas copias
son intencionales: la primera pertenece al generador, la segunda es su archivo
operativo; respaldar ambas bases y sus volúmenes privados.

La instalación Windows usa optimize-autoloader=false. Dependencias vendor,
credenciales .env y archivos generados no deben subirse a Git.
