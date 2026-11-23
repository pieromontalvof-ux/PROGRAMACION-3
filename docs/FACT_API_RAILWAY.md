# fact_api online en Railway

Implementación del 23/11/2026 en el proyecto `extraordinary-gentleness`, servicio
`MULTIAGENTE`, entorno `production`.

## Resultado operativo

- Se reutilizan el servicio web, PostgreSQL y el volumen `/data` existentes.
- PHP-FPM y Nginx sirven Laravel solo en localhost. La única entrada pública
  continúa siendo Flask con autenticación y permisos por local.
- Se aplicaron las migraciones faltantes de clientes, cola y escalado sin restaurar
  datos locales. Las 14 ventas existentes se conservaron.
- Laravel mantiene sus tablas en el esquema `fact_api`; Barbarito conserva `public`.
- Hay cuatro locales activos configurados. Los trabajadores escalan de uno a dos,
  con el límite configurable hasta cuatro según recursos disponibles.
- La venta 14 se procesó sin crear otro cobro: A4 y ticket completados en el primer
  intento, archivos verificados por SHA-256 y descarga autenticada desde el dominio
  público correcta para ambos formatos.

## Dónde usarlo

Entrar a Salón → Diario de ventas → seleccionar la venta → Ver PDF A4 o ticket.
En ventas anteriores sin encargo todavía se puede solicitar el documento desde
el diario. Al cobrar una nueva venta se encola automáticamente; se puede regresar
al salón mientras se genera el PDF.

Si la página estaba abierta antes del despliegue, actualizar con Ctrl+F5. La
búsqueda de clientes registrados ya dispone de su tabla; Factiliza usa su token
de Railway y es independiente del generador de documentos.

## Archivos y credenciales

- Original generado por Laravel: `/data/fact_api/laravel_storage/app/private/`.
- Copia que entrega Barbarito: `/data/fact_api_documents/`.
- Claves internas: `/data/fact_api/runtime-secrets.json`, privado; no se publican
  en Git ni se muestran en el navegador.
- El arranque y sus procesos: `backend/scripts/cloud_runtime.py`.
- Configuración interna: `deploy/php-fpm.conf` y `deploy/fact-api-nginx.conf`.
- Procedimiento y variables: `DEPLOY.md`.

El volumen conserva archivos entre despliegues. No se genera una copia pública
de las facturas ni se transfieren automáticamente los PDF de la computadora.

## Límites

Solo DEMO: no hay firma digital ni envío a SUNAT. Las boletas/facturas generadas
no tienen validez tributaria. Los PDF originales de proveedores se conservan como
adjuntos; los resúmenes de recepción no son una factura emitida por el proveedor.

No se añadieron servicios o planes de pago; el uso de CPU, memoria y volumen
consume los recursos de la cuenta Railway existente.
