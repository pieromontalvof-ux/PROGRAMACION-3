# fact_api en Barbarito: operación, archivos y PostgreSQL

## Qué está instalado

Barbarito conserva React y Flask/Python. En `services/fact_api` está una copia
del proyecto https://github.com/angelitosystems/fact_api, con una ampliación propia.
No se ha sustituido Flask por FastAPI: fact_api es el nombre del servicio Laravel.

Hay dos bases PostgreSQL independientes en el mismo servidor local:

- `barbarito`: ventas, clientes, OC, recepciones, cola y seguimiento.
- `fact_api_demo`: tablas de Laravel, empresas, sucursales, terceros, documentos y archivos generados.

Configuración actual: **DEMO**, empresa ficticia, sin credenciales SOL operativas,
sin certificado, sin envío a SUNAT. Los PDF lo indican en todas sus variantes.
No se generan XML firmados ni constancias CDR ficticias. Esto es integración real
entre programas y bases locales, no emisión fiscal real ni certificación tributaria.

Se configuraron los locales activos existentes. La tasa 18 de las ventas es una
configuración de demostración, no una clasificación tributaria verificada de cada
producto. Las compras conservan los impuestos registrados en su factura: no se
convierten todos los productos en exonerados.

## Cómo ponerlo en marcha

Desde la raíz, en PowerShell:

```powershell
# Solo para instalar o aplicar cambios de estructura/configuración local:
backend/.venv/Scripts/python.exe backend/scripts/configure_fact_api.py

# Servicio y supervisor automático en segundo plano, ventanas ocultas:
powershell -ExecutionPolicy Bypass -File backend/scripts/start_fact_api.ps1 -Workers 1

# Consulta de salud y resumen de la cola, sin crear ventas ni compras:
backend/.venv/Scripts/python.exe backend/scripts/check_fact_api.py
```

El inicio habitual `INICIAR_BARBARITO.bat` también intenta arrancar esta integración
si encuentra su configuración. Para ejecutar procesos en primer plano, usar dos terminales:

```powershell
backend/.venv/Scripts/python.exe backend/scripts/run_fact_api_service.py
backend/.venv/Scripts/python.exe backend/scripts/run_fact_api_worker.py
```

Se necesita además el backend y frontend habituales. Tras cambios de código o `.env`,
reiniciar el backend y el supervisor. El inicio predeterminado activa escalado
automático entre 1 y 4 workers. Revisa la cola cada cinco segundos: crece con
cuatro trabajos por worker o esperas mayores de quince segundos, con diez segundos
entre crecimientos. Tras sesenta segundos sin trabajo se retira un worker, hasta
volver al mínimo. Cada uno termina su operación antes de salir. `-Workers 2` fija
un mínimo de dos; para un número fijo usar `-Manual -Workers 2`, sin supervisor activo.

Un bloqueo PostgreSQL garantiza un supervisor por base. Los workers verifican su
identidad y heartbeat: si cambia o pasan veinte segundos sin señal, se retiran al
terminar su trabajo. Cuatro reservas PostgreSQL adicionales limitan la concurrencia
incluso al reemplazar un supervisor caído. El circuito abierto o errores transitorios
recientes impiden aumentar la carga. No requiere Redis ni escalado de pago.

Para cerrar ordenadamente el supervisor iniciado por el script:

```powershell
New-Item -ItemType File -Path .local/fact-supervisor.stop -Force
```

Esperar hasta que el estado indique cero workers antes de iniciar otro modo.
El siguiente inicio elimina esa señal. Consulta del estado:

```sql
SELECT minimo,maximo,activos,objetivo,listos,ocupados,pausado,actualizado_en
FROM fact_api_escalado;
```

En esta PC el servidor incorporado de PHP no se mantuvo activo. Para desarrollo
Windows se proporciona `run_fact_api_service.py`: recibe HTTP en 127.0.0.1:8091 y
ejecuta el núcleo HTTP real de Laravel por PHP CLI para cada petición. No simula
fact_api. Admite hasta cuatro procesos PHP simultáneos; el resto recibe 429.
Para publicación se debe usar un servidor PHP apropiado, por ejemplo PHP-FPM y nginx,
volúmenes persistentes y supervisión de procesos. El adaptador local no reemplaza eso.

El archivo `services/fact_api/.env` tiene la configuración privada de Laravel.
`backend/.env` conserva URL y token del puente. No pegar claves en chats, documentos
ni Git. Los programas no imprimen esas claves.

## Operación de ventas

1. El responsable cobra la mesa en Salón con el flujo habitual.
2. Flask registra el cobro y consumo de inventario.
3. Antes de confirmar esa misma transacción, agrega el trabajo de documento a la cola.
4. Al confirmar, el pago está registrado aunque la API esté temporalmente caída.
5. El worker toma el trabajo, llama al puente Laravel y obtiene su identificador.
6. Laravel usa `DocumentService::createInvoice/createBoleta` para guardar la empresa/sucursal/cliente y el documento nativo. Continúa los correlativos existentes y comprueba que base, IGV y total coincidan con el cobro.
7. El worker solicita PDF A4 y ticket de 80 mm, los archiva y registra sus huellas.
8. En el comprobante y Diario de ventas aparece el panel `Documento de prueba · fact_api`.
9. La pantalla actualiza el estado mientras hay trabajo pendiente y permite descargar.

Para ventas anteriores sin trabajo, `Generar PDF de prueba` encola el documento.
No vuelve a cobrar ni consume stock. El PDF generado no sustituye el registro interno.

Si se corrige el tipo o cliente de la venta, se conserva la versión anterior y se
encola una nueva instantánea. Si se anula, los trabajos previos se marcan obsoletos.
Un PDF ya creado permanece histórico; no se borra ni se presenta como reversión SUNAT.
La integración real futura necesitaría las notas/anulaciones tributarias pertinentes.

## Operación de compras

1. Crear/enviar una OC y registrar la recepción/factura del proveedor.
2. Barbarito guarda los datos comerciales, cantidades recibidas y pendientes habituales.
3. En la misma transacción se encola el registro de documento de compra si hay importes.
4. El worker envía proveedor, OC, líneas e impuestos a Laravel.
5. Laravel marca ese tercero como proveedor y guarda el documento con origen `COMPRA`.
6. No crea una factura de venta ni envía a SUNAT la factura del proveedor.
7. Genera una **vista interna de la factura recibida**, A4/ticket, identificada como tal.
8. En Historial de recepciones, expandir el detalle para ver el panel y descargar.
9. `Adjuntar original del proveedor` permite conservar su PDF o XML real, máximo 5 MB.
   Es un archivo independiente de la vista interna generada. No se extraen sus líneas
   automáticamente y cargarlo no demuestra aceptación SUNAT.

Recepciones antiguas sin importes comerciales no generan documentos inventados.
Las entregas adicionales cambian lo recibido, no los importes de la factura completa.
Cambiar la cabecera de factura genera una versión nueva si cambia la instantánea.

## Recorrido de archivos: venta, desde la pantalla al PDF

| Orden | Archivo | Responsabilidad |
|---|---|---|
| 1 | `frontend/src/features/salonPayments/SalonPaymentPage.tsx` | Recibe cliente/pago y solicita cobrar. |
| 2 | `frontend/src/services/salonService.ts` | Envía la solicitud autenticada al backend. |
| 3 | `backend/app/__init__.py` | Registra las rutas del salón y la integración. |
| 4 | `backend/app/modules/salon/salon_payments.py` | Valida sesión/cuenta; guarda cobro, consumo y trabajo en una transacción. |
| 5 | `backend/app/modules/facturacion/service.py` | Lee la configuración del local y obtiene los datos de la fuente. |
| 6 | `backend/app/modules/facturacion/contract.py` | Convierte esos datos al contrato JSON del puente, verifica importes y fecha de Lima. |
| 7 | `backend/app/modules/facturacion/repository.py` | Guarda UUID/huella/instantánea; reclama trabajos y confirma estados con protección de turno. |
| 8 | `backend/scripts/run_fact_api_worker.py` | Mantiene vivo el proceso trabajador. |
| 9 | `backend/app/modules/facturacion/worker.py` | Envía el trabajo, solicita PDF y guarda el resultado. |
| 10 | `backend/app/modules/facturacion/transport.py` | HTTP autenticado con timeout, respuesta acotada y sin redirecciones. |
| 11 | `backend/scripts/run_fact_api_service.py` | Adaptador de desarrollo Windows que recibe HTTP y llama a PHP. |
| 12 | `services/fact_api/barbarito-cli-http.php` | Construye la petición y la entrega al núcleo HTTP de Laravel. |
| 13 | `services/fact_api/bootstrap/app.php` | Arranca Laravel; conserva exactamente los valores JSON del puente. |
| 14 | `services/fact_api/routes/api.php` y `routes/barbarito.php` | Publican las rutas del puente en modo demo. |
| 15 | `services/fact_api/app/Http/Middleware/BarbaritoAccess.php` | Comprueba token privado y modo de pruebas. |
| 16 | `services/fact_api/app/Http/Controllers/Api/BarbaritoController.php` | Valida importes, deduplica por UUID/huella, guarda documentos y entrega archivos. |
| 17 | `services/fact_api/app/Models/{Company,Branch,Client,Invoice,Boleta}.php` | Modelos originales reutilizados para guardar las entidades. |
| 18 | `services/fact_api/app/Services/DocumentService.php` y `PdfService.php` | Creación y PDF originales de fact_api para ventas; adaptación de IGV incluido y modo de pruebas. |
| 19 | `services/fact_api/resources/views/pdf/a4/`, `80mm/` y `components/` | Plantillas originales A4/ticket, con logo Barbarian y aviso de falta de validez tributaria. Para compras se conserva exclusivamente el resumen interno de `BarbaritoPdfService` / `pdf/barbarito/document.blade.php`. |
| 20 | `backend/app/modules/facturacion/worker.py` | Archiva los bytes recibidos con una ruta por turno y SHA-256 (huella para detectar cambios). |
| 21 | `backend/app/modules/facturacion/routes.py` | Devuelve estado/métricas y descarga únicamente archivos del local autorizado. |
| 22 | `frontend/src/components/FactApiPanel.tsx` | Muestra estados, reintentos, vistas previas y descargas; también permite ver el PDF original del proveedor. No contiene el token externo. |

En compras, el inicio pasa por `PendingReceiptsPage`/`recepciones/routes.py` y
`recepciones/service.py`, que guardan `factura_recepcion` mediante su repositorio
y `invoice_storage.py`. Después se incorpora al mismo recorrido desde el paso 5.
Los originales pasan por `FactApiPanel` → `facturacion/routes.py` → `attachments.py`
→ almacenamiento privado y tabla `fact_api_adjunto`.

## Qué queda en cada tabla

En `barbarito`:

| Tabla/vista | Contenido |
|---|---|
| `salon_cobro` | Pago original, cliente y detalle conservado del consumo. |
| `cliente_comercial` | Directorio local de clientes, independiente de Factiliza/fact_api. |
| `proveedor` | Proveedor y sus datos comerciales. |
| `orden_compra`, `orden_compra_detalle` | Qué se solicitó. |
| `factura_recepcion` | Factura recibida; `datos_factura` contiene importes y líneas. |
| `factura_recepcion_detalle` | Cantidades recibidas. |
| `fact_api_config` | Local activo, empresa de prueba, series y tasa de demostración. |
| `fact_api_operacion` | Cola durable: UUID, origen, versión, instantánea, huella, estado y reserva. |
| `fact_api_intento` | Inicio/fin/duración/HTTP de cada intento, sin tokens ni respuesta completa. |
| `fact_api_documento` | Correspondencia con Laravel, numeración e importes. |
| `fact_api_archivo` | Ruta privada, formato, tamaño y huella de PDF generado. |
| `fact_api_adjunto` | Originales PDF/XML aportados por el proveedor. |
| `fact_api_circuito` | Pausa compartida cuando la API falla repetidamente. |
| `fact_api_escalado` | Supervisor, workers activos/objetivo, cola y última señal de actividad. |
| `fact_api_seguimiento` | Vista que une cola, local y documento para consultas rápidas. |

En `fact_api_demo`:

- `companies`, `branches`, `clients`: empresa, sucursales y terceros.
- `clients.barbarito_customer`/`barbarito_supplier`: distinguen cliente, proveedor o ambos.
- `invoices`, `boletas`: documentos nativos de venta de prueba (`estado_sunat='DEMO'`).
- `barbarito_documents`: UUID compartido, origen VENTA/COMPRA, datos inmutables,
  huella y referencia al documento nativo cuando corresponde.
- `barbarito_files`: rutas y huellas de los archivos generados.
- Las demás tablas upstream permanecen para su funcionalidad original; no afirmar
  que todos sus servicios/notas/guías se probaron ni que están publicados por el puente.

Los PDF no van dentro de las columnas ni a GitHub. Laravel conserva su ejemplar en
`services/fact_api/storage/app/private/barbarito`. Barbarito conserva una copia de
archivo operativo en `backend/instance/fact_api_documents`, configurable mediante
`FACT_API_DOCUMENTS_DIR`. Esta duplicación es deliberada: permite descargar aunque
el generador esté caído. Ambas copias deben incluirse en respaldos.

## Si se corta la conexión o cae un worker

- Cobro y trabajo se confirman juntos; no se llama a la API dentro de esa transacción.
- Los workers reservan filas usando `FOR UPDATE SKIP LOCKED`: no toman el mismo turno.
- Reserva de tres minutos; el HTTP tiene timeout de veinte segundos y límites de tamaño.
- Un turno vencido puede recuperarse. El worker viejo no puede confirmar resultados
  ni sobrescribir los archivos del nuevo: cada turno escribe en una ruta distinta.
- La API deduplica por UUID dentro de una transacción y compara la huella del JSON.
  Igual UUID + mismos datos devuelve el documento existente; otros datos devuelve 409.
- Creación de PDF se serializa por documento/formato y se publica mediante renombrado.
- Hay hasta seis intentos automáticos, con espera creciente y dispersión aleatoria.
  429 respeta `Retry-After` acotado; errores de credenciales y de datos requieren revisión.
- Tras tres respuestas transitorias fallidas, la cola se pausa treinta segundos.
- `REVISION` significa resultado que necesita comprobarse, no inexistencia del documento.
- El reintento manual conserva el UUID y añade otro presupuesto de seis intentos;
  no borra el historial y no permite reactivar fuentes obsoletas.
- Hay autoescalado local acotado; no hay alertas externas ni borrado automático de
  historial/archivos. Definir retención y monitorización externa antes
  de un uso empresarial real. Los archivos huérfanos de procesos interrumpidos
  pueden requerir limpieza controlada, nunca borrar documentos referenciados.

## Consultas para mostrarlo en PostgreSQL

Abrir pgAdmin → base `barbarito` → Query Tool. Primero comprobar la conexión:

```sql
SELECT current_database(), current_user;
SELECT table_schema, table_name FROM information_schema.tables
WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name;
SELECT column_name,data_type FROM information_schema.columns
WHERE table_schema='public' AND table_name='fact_api_operacion' ORDER BY ordinal_position;
```

Seguimiento general, incluyendo fallos y número de documento:

```sql
SELECT * FROM fact_api_seguimiento ORDER BY creado_en DESC LIMIT 50;
SELECT id_local,origen,estado,count(*) FROM fact_api_operacion
GROUP BY id_local,origen,estado ORDER BY 1,2,3;
```

Elegir un UUID de esa primera consulta y seguirlo (reemplazar el ejemplo):

```sql
SELECT id_operacion,origen,id_origen,version,estado,obsoleto,payload
FROM fact_api_operacion WHERE id_operacion='00000000-0000-4000-8000-000000000000';
SELECT numero,inicio,fin,duracion_ms,http_status,resultado FROM fact_api_intento
WHERE id_operacion='00000000-0000-4000-8000-000000000000' ORDER BY numero;
SELECT d.numero,d.estado,a.formato,a.ruta,a.bytes,a.sha256
FROM fact_api_documento d LEFT JOIN fact_api_archivo a USING(id_documento)
WHERE d.id_operacion='00000000-0000-4000-8000-000000000000';
```

Desde la venta hasta el archivo:

```sql
SELECT c.id_cobro,c.id_local,c.tipo,c.total,o.id_operacion,o.estado,d.numero,a.formato,a.ruta
FROM salon_cobro c
LEFT JOIN fact_api_operacion o ON o.origen='VENTA' AND o.id_origen=c.id_cobro
LEFT JOIN fact_api_documento d USING(id_operacion)
LEFT JOIN fact_api_archivo a USING(id_documento)
ORDER BY c.id_cobro DESC,o.version DESC LIMIT 50;
```

Desde el proveedor/OC hasta la factura y documento:

```sql
SELECT p.nombre AS proveedor,oc.codigo AS oc,f.numero_factura,oc.id_local,
 f.datos_factura->>'total' AS total_factura,o.id_operacion,o.estado,d.numero,a.formato
FROM factura_recepcion f JOIN proveedor p USING(id_proveedor)
JOIN orden_compra oc USING(id_orden_compra)
LEFT JOIN fact_api_operacion o ON o.origen='COMPRA' AND o.id_origen=f.id_factura_recepcion
LEFT JOIN fact_api_documento d USING(id_operacion)
LEFT JOIN fact_api_archivo a USING(id_documento)
ORDER BY f.id_factura_recepcion DESC LIMIT 50;
SELECT id_factura_recepcion,formato,bytes,sha256,creado_en FROM fact_api_adjunto;
```

Para revisar el otro extremo, abrir otra conexión a `fact_api_demo` y ejecutar:

Usar la conexión administrativa de PostgreSQL o el usuario dedicado
`fact_api_demo` configurado en el `.env` privado de Laravel. El usuario `multi`
de Barbarito no recibe acceso a las tablas privadas del servicio externo.

```sql
SELECT id,origin,source_reference,number,state,native_type,native_id,payload_hash
FROM barbarito_documents ORDER BY created_at DESC LIMIT 50;
SELECT document_id,format,path,bytes,sha256 FROM barbarito_files;
SELECT id,razon_social,barbarito_customer,barbarito_supplier FROM clients;
SELECT id,numero_completo,estado_sunat,mto_imp_venta FROM invoices;
SELECT id,numero_completo,estado_sunat,mto_imp_venta FROM boletas;
```

`fact_api_operacion.id_operacion`, `fact_api_documento.id_externo` y
`barbarito_documents.id` identifican el mismo recorrido. PostgreSQL no une bases
distintas directamente con un JOIN normal: comparar ese UUID en ambas conexiones.
Estas consultas muestran datos personales si se selecciona el payload: usar una
sesión autorizada y no publicar resultados completos en capturas o repositorios.

## Qué falta para emisión real

Empresa habilitada, credenciales/certificado y configuración tributaria reales;
integrar y probar XML firmado, envío, respuestas CDR, correcciones tributarias,
conciliación y procedimientos operativos. Cambiar una variable DEMO no completa
esa integración. La búsqueda DNI/RUC sigue siendo Factiliza y no emite documentos.

## Evidencia de verificación de esta entrega

- Suite backend: 742 pruebas, 600 correctas y 142 omitidas por condiciones de entorno.
- Suite adicional PostgreSQL aislado: 41 correctas, incluyendo cola concurrente,
  recuperación de workers, permisos por local, originales y cobro con encolado atómico.
- Servicio Laravel local: dos pruebas HTTP correctas con creación simultánea,
  repetición tras respuesta perdida, conflicto por contenido distinto y PDF A4/ticket.
- Interfaz: 151 pruebas correctas, revisión estática y compilación correctas.
- Cuatro compras y tres ventas existentes produjeron siete documentos y catorce
  PDF verificados por SHA-256. El cuarto local no tenía una venta disponible para
  ese ejemplo; no se inventó un pago para cubrirlo.
- Dos revisiones independientes de código y corrección de sus hallazgos de
  fecha, concurrencia, versiones e integridad. No se hicieron pruebas tributarias
  reales ni se activó SUNAT. Secretos, certificados y documentos privados excluidos de Git.
