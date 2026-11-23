# Formatos originales de fact_api y medición local

Configurado el 21 de noviembre de 2026. No se requiere otra plataforma: se
reutilizan servicios, modelos y plantillas incluidos en fact_api.

## Cómo verlo

- Salón → Diario de ventas → seleccionar una venta → Ver PDF A4 o Ver ticket de
  80 mm. También están disponibles desde el comprobante al finalizar el cobro.
- Al finalizar el cobro, el visor abre automáticamente el A4 cuando la cola lo
  deja disponible. No vuelve a cobrar para mostrar el documento. Se puede cambiar
  a ticket, descargar o cerrar la vista previa.
- Recepción de productos → Historial → abrir la factura → adjuntar su PDF/XML
  original. Ver original PDF abre exactamente el archivo del proveedor. El XML
  se descarga. El resumen de recepción generado continúa siendo interno.
- Si ya estaba abierta una vista previa al actualizar el programa, cerrarla y
  volverla a abrir para cargar el PDF actualizado.

En esta instalación local hay otro proyecto que ocupa el puerto 5000. El backend
de esta carpeta funciona en 5001; `frontend/.env.local` configura
`VITE_API_URL=http://127.0.0.1:5001/api`. El frontend de Barbarito funciona en 5173.
Ese archivo local está excluido de Git. En otro equipo debe configurarse la URL
que corresponda a su backend; el puerto no cambia los documentos guardados.

## Qué se reutiliza y qué se adapta

Las ventas usan `DocumentService::createInvoice/createBoleta`, los modelos
Company, Branch, Client, Invoice/Boleta y Correlative, y
`PdfService::generateInvoicePdf/generateBoletaPdf`. Los diseños son los originales
de `resources/views/pdf/a4` y `80mm`, con el logo Barbarian. Se conservan sus
tablas, cabecera, totales e importe en letras; no se añade otro generador.

El puente adapta los precios del salón que ya incluyen IGV. La base, impuesto y
total se verifican también por línea. Un S/15,50 con base S/13,14 e IGV S/2,36
conserva exactamente S/15,50. Los reintentos devuelven la misma referencia y
numeración; cambiar la plantilla no vuelve a cobrar ni crea otra venta.

Los números anteriores se conservan y la numeración siguiente continúa desde el
mayor número existente de la serie. A4 y ticket muestran `numero_completo`, sin
añadir distintos ceros según el formato. La migración
`2026_11_21_100000_scope_clients_by_company.php` permite que un mismo DNI/RUC se
registre en distintas empresas sin mezclar sus fichas.

La cola, workers automáticos, permisos por local, trazabilidad, originales y
archivos privados con SHA-256 siguen funcionando. No se añaden tablas a Barbarito
para esta adaptación. La migración modifica la unicidad de clientes en
`fact_api_demo`; el esquema de referencia está en `database/fact_api_schema.sql`.

La empresa sigue en DEMO: no hay envío SUNAT, firma digital ni CDR. El PDF lo
indica y no muestra mensajes de autorización o verificación que no corresponden.
Las facturas de proveedores no se emiten como ventas nuestras.

## Medición reproducible

Resultados agregados: `docs/FACT_API_TIEMPOS.json`. Son cinco documentos nuevos de
una línea, alternando boleta y factura, contra el Laravel local real. Las series
TB01/TF01 y referencias BENCH identifican estas pruebas. No se cobran mesas ni
se mueve inventario. No se usan personas reales.

Promedios de la medición local del 21/11/2026 a las 10:13, hora de Lima:

| Operación | Promedio |
| --- | ---: |
| Registrar documento | 0,40 s |
| Generar A4 por primera vez | 1,50 s |
| Generar ticket por primera vez | 1,50 s |
| Registrar y obtener ambos PDF | 3,39 s |
| Recuperar A4 ya generado | 0,40 s |
| Recuperar ticket ya generado | 0,34 s |

El tiempo percibido en pantalla puede ser mayor por la cola y la frecuencia de
consulta del estado. Estos tiempos no incluyen una respuesta de SUNAT.

Desde `backend`:

```powershell
.venv/Scripts/python.exe scripts/benchmark_fact_api.py --samples 5 --output ../docs/FACT_API_TIEMPOS.json
```

El script solo admite localhost y exige confirmar DEMO. Mide por separado POST,
repetición idempotente, primera generación de A4/ticket y recuperación de PDF
guardado. El total suma registro y las dos primeras generaciones; excluye las
consultas de comprobación. No mide espera en cola, refresco de pantalla ni SUNAT.
Con cinco muestras el percentil 95 es exploratorio, no una garantía de servicio.
Influyen la máquina, carga, tamaño del documento y el arranque de PHP por petición
del adaptador Windows. Un PDF ya generado se devuelve desde el archivo guardado.

## Actualizar representaciones anteriores

```powershell
# Solo cuenta; no modifica datos.
.venv/Scripts/python.exe scripts/refresh_fact_api_pdfs.py
# Actualiza archivos de ventas completadas sin alterar número, cobro o UUID.
.venv/Scripts/python.exe scripts/refresh_fact_api_pdfs.py --apply
```

Se conserva el archivo físico anterior. Antes de cambiar la ruta registrada se
vuelve a comprobar que la operación siga completada y vigente. No se actualizan
operaciones anuladas u obsoletas. Los nuevos PDF de Laravel se guardan en una
carpeta privada versionada `native-v3`; nunca se publican mediante storage:link.

## Comprobaciones realizadas

- Pruebas HTTP: concurrencia/repetición sin duplicado, factura con IGV incluido,
  compra como resumen separado y rechazo de desglose tributario incoherente.
- Prueba transaccional PHP: mismo documento de cliente en dos empresas distintas
  y redondeo nativo. Las escrituras de la prueba se revierten.
- Lectura y revisión visual de A4 y ticket: logo, numeración consistente, código,
  importes y aviso de demostración; sin enlaces ni autorización SUNAT ficticios.
- Pruebas de interfaz para ver el original y conservar los visores de ventas,
  cambio de local y descarga. Compilación y lint de interfaz.
