# Agentes del asistente Barbarito

## Administración de instrucciones y documentos

El menú Asistente IA separa Conversación, Ver agentes y Archivos de agentes.
Mapa y biblioteca requieren Administrador tanto en las rutas de interfaz como en la API.
Archivos de agentes muestra un solo editor de la skill seleccionada. Sus flujos son
editar → Validar skill → Guardar skill, o subir/ver archivos → Actualizar skill con
archivos → Validar skill → Guardar skill. El mapa recibe las skills guardadas vigentes.
La matriz de accesos está exclusivamente en el menú Permisos de agentes.

La API `/api/asistente-ia/biblioteca` guarda JSON privado por agente en
`backend/instance/agent_library/` (o `AGENT_LIBRARY_DIR`). Esta carpeta debe incluirse
en los respaldos de la instalación: no se guarda en Git ni en el backup PostgreSQL.
Los bloqueos del sistema operativo y revisiones impiden perder cambios entre procesos.
Los cambios se guardan como configuración versionada, sin escribir archivos de código.
El runtime sustituye las instrucciones/skills del agente por la versión aplicada y
cruza sus accesos con los recursos soportados y los permisos nativos del perfil/local.
Las instrucciones adicionales antiguas se incorporan al texto inicial para conservarlas.
Los formularios y la confirmación de borradores también revalidan esos accesos.
No requiere reiniciar ni entrenar después de aplicar una configuración.

El Revisor de configuración (`agents/configuracion/agent.py`) no tiene herramientas
ni permisos de escritura. Lee la propuesta y todos sus documentos hasta un máximo
de 120000 caracteres; si excede el límite rechaza la revisión, sin truncar silenciosamente.
Devuelve faltantes, necesidades de acceso/delegación, conflictos y recomendaciones.
No amplía permisos ni garantiza que un procedimiento fijo cambie por editar un prompt.
El Actualizador de skills (`agents/actualizador_skills/agent.py`) propone texto a partir
de los originales seleccionados; nunca guarda configuración ni cambia accesos.
El Validador es independiente y señala permisos necesarios y para qué, información
faltante y conflictos. Esos pendientes bloquean Guardar skill; las sugerencias opcionales no.
Las rutas integrales antiguas de revisión/guardado devuelven 410 para evitar eludir el flujo.
Una revisión firmada dura 15 minutos y está ligada a administrador/perfil/local,
agente, revisión y hash de configuración/documentos. Cualquier cambio obliga a revisar otra vez.
El guardado de skills conserva los accesos. Guardar permisos usa su propia ruta y
conserva las skills, instrucciones y estado de documentos. Un cambio de permisos
invalida la revisión anterior; la pantalla de skills puede revalidar sin perder su texto.

Formatos: TXT/MD/CSV/JSON UTF-8, DOCX, PDF y PNG/JPG/WebP, hasta 2 MB por archivo,
200000 caracteres extraídos para documentos de texto y máximo 10 archivos por agente.
Se conserva el original en base64 dentro del almacenamiento privado, además del texto
extraído cuando procede. Un endpoint autenticado exclusivo de Administrador entrega el
original con MIME fijo, nosniff y no-store. Los documentos antiguos solo conservan su texto.
El visor usa URLs blob revocables para imágenes/PDF y texto para otros documentos,
con descarga del original. No se ejecutan ni se extraen archivos a rutas indicadas por usuarios.
El análisis usa input_image e input_file de Responses, con un máximo de 12 MB binarios
por solicitud y sin pegar el base64 dentro de instrucciones de texto. Referencias oficiales:
[entradas de archivos](https://developers.openai.com/api/docs/guides/file-inputs) e
[imágenes y visión](https://developers.openai.com/api/docs/guides/images-vision).
El contexto operativo incorpora hasta 24000 caracteres de documentos
por agente, en orden, avisando al modelo si se truncó. La interfaz permite revisar ese texto.
Los documentos nuevos quedan pendientes hasta revisar/aplicar la configuración; al
eliminar uno se retira su referencia. Los documentos son referencias; los permisos, la confirmación y los datos vigentes de
las rutas nativas siguen siendo la autoridad. Los archivos visuales se incorporan a través
de la skill actualizada y validada; no se adjuntan en cada conversación operativa.
La consulta directa de preparación de recetas
continúa usando las recetas registradas, sin sustituirlas por documentos adicionales.

Compras, Demanda y Eventos también reciben las referencias del Coordinador, sin mezclarlas
con el historial truncado del navegador. Los pasos deterministas del flujo no son editables.

## Consultas de preparación

«Cómo se prepara una hamburguesa» se dirige a Recetas, también con «prepra».
`orchestrator/recipe_answers.py` consulta las recetas autorizadas por las rutas
nativas y responde directamente con los datos guardados, sin generación del modelo.
Si coinciden varios artículos/presentaciones, ofrece botones para elegir la receta.
Si faltan instrucciones o no hay una receta activa, lo informa sin completar pasos.
Esta consulta no prepara cambios, conserva los permisos y puede hacerse dentro de
un pedido guiado sin perder el flujo de compra. Las instrucciones comunes del runtime
también prohíben reemplazar datos del negocio por conocimiento general.
La búsqueda admite errores leves de letras y transposiciones en nombres registrados;
primero busca coincidencias exactas. Las coincidencias aproximadas ambiguas requieren
elección humana. Códigos, identificadores, cantidades y unidades no se corrigen por similitud.

## Pedido guiado

«Quiero hacer un pedido» inicia el flujo del Coordinador: Eventos cercanos →
opciones de análisis → consultas opcionales → porcentaje elegido → borrador de Compras.
Las opciones incluyen un evento pasado parecido (requiere fechas, no hay un archivo
que vincule eventos y ventas), ventas/consumo desde la última orden enviada del local
y cobertura estimada del stock. Después de un análisis se ofrecen los demás.
Se puede omitir el análisis y continuar. Un fallo de eventos no bloquea el pedido.

`orchestrator/purchase_flow.py` conserva un estado firmado por dos horas, ligado
a usuario/perfil/local; la pantalla lo guarda en su workspace y lo envía al siguiente
turno. La investigación solo expone consultas. Una pregunta hipotética sobre porcentajes
no selecciona el margen. La propuesta conserva la confirmación y rutas nativas existentes.

## Demanda y rotación

El agente `demanda` analiza toda la carta y todos los insumos del local activo.
Ejemplos: «¿Qué tiene más salida?», «Analiza la rotación de cervezas»,
«¿Cuánto durará la IPA?» o «Prepara un pedido según la rotación» (Compras).
Por defecto usa 30 días; se puede pedir un rango de hasta 367 días.
Requiere perfil Gerente/Supervisor y permisos de consulta de stock (15) y ventas (37).

La herramienta `analizar_demanda` comparte con Compras el informe de
`GET /api/inventario-operativo/demanda?desde=AAAA-MM-DD&hasta=AAAA-MM-DD`.
No modifica stock ni recalcula recetas antiguas: toma artículos de cobros registrados
y el consumo por producto guardado en el movimiento de cada cobro. Los ingredientes
compartidos se suman por producto, conservando su unidad. Se muestran ingresos
registrados por separado, no como ventas. Compras conserva su fórmula y confirmación.

La cobertura usa stock actual dividido entre consumo promedio por días calendario;
no representa disponibilidad diaria ni seguimiento de lotes. Siete días es una alerta
orientativa, no el plazo de un proveedor. Sin datos no se atribuye rechazo al producto.
La información comercial de categoría/artículo se toma del catálogo actual;
las cantidades consumidas proceden del movimiento histórico. El stock es el actual,
incluso cuando se consulta un periodo histórico. Sin migraciones de cobros/jornadas,
el análisis indica que falta instalar esas funciones, sin inventar resultados.
Las presentaciones se agrupan por identidad aunque cambie su nombre. Las elecciones
de promociones se incluyen en su cantidad; el combo conserva su propia identidad
y su importe no se distribuye ni se duplica entre elecciones.

Pruebas SQL aisladas en Windows: `backend/.venv/Scripts/python.exe backend/scripts/check_demand_postgres.py`.
El script crea y cierra un clúster temporal local con datos ficticios; no usa `.env`.

## Formularios de catálogo en el chat

«Crear categoría de productos», «crear proveedor» y «crear producto» abren formularios
directos mediante `/api/asistente-ia/preparar`, sin llamada al modelo ni escritura.
El especialista también dispone de `abrir_formulario` para otras expresiones de la
misma intención. Las tres skills específicas se muestran en el inspector de agentes.
`POST /formulario` actualiza opciones reales; `POST /formulario/preparar` valida los
campos y guarda únicamente una propuesta en el almacenamiento de borradores existente.
El usuario revisa y confirma en `/realizar`, que conserva los permisos, la auditoría
y la protección contra reenvíos existentes. Los formularios no requieren una clave
del proveedor de IA; las consultas libres y el dictado mantienen su configuración.
Al cambiar un campo, la interfaz exige revisar otra vez antes de confirmar.

Los formularios incluyen pasos dependientes: Productos → Categoría de productos /
Proveedor; Proveedor → Categoría de productos; Presentaciones → Categoría de carta /
Menaje. `CatalogWorkflow.tsx` conserva los valores del paso padre al abrir otro,
confirma cada requisito mediante los borradores existentes, actualiza las opciones
y retoma el padre con la referencia creada. El usuario puede volver sin crear.
Solo se muestran dependencias creables autorizadas por el backend. Si una creación
se confirma pero falla actualizar opciones, el siguiente intento únicamente retoma
el flujo; no vuelve a crear el requisito.

El agente de Eventos carga `modules/asistente_ia/skills/compras_eventos/SKILL.md`.
Al iniciar el pedido guiado o solicitar eventos consulta la dirección del local activo, con sede,
período, recinto y distrito, público, edades publicadas, descripción breve y fuente.
La cercanía se señala únicamente cuando hay sustento; Santa Anita conserva su dirección
sin número y no se asume un tramo preciso. Las festividades generales se separan de
los eventos locales. Los porcentajes de compra los decide el gerente.

Compras pregunta qué porcentaje de incremento aplicar antes de preparar un pedido si no se indicó.
Ese margen reemplaza el 20% fijo y se aplica al consumo antes de restar stock.
El formulario de Compras exige elegir un porcentaje (0% permite pedir sin incremento).

Compras carga su propia skill `skills/compras/SKILL.md` y consulta la base sin
búsquedas web automáticas. Eventos entrega el informe directamente, sin una segunda
llamada al modelo. Recepción consulta pendientes e historial con permisos 24 y 32;
solo prepara entregas con cantidades, factura y fecha verificadas por la persona.
Realizar revalida los pendientes y usa la ruta nativa de recepción, sin reenvíos.
Inventario mantiene sus consultas y propuestas; el conteo físico y la investigación
de diferencias en tienda son humanos. No existe otro agente de conteo.

`orchestrator/router.py` dirige las solicitudes a Catálogo de insumos,
Inventario, Compras, Recepción, Eventos o uno de seis especialistas definidos en
`catalog_specialists.py`: Categorías de carta, Menajes, Presentaciones de venta,
Subproductos, Recetas y Promociones. Cada uno carga su propio `SKILL.md`. El enrutamiento no
requiere otra llamada al modelo y conserva el especialista en correcciones breves.
Una nueva tarea explícita tiene prioridad sobre el borrador anterior.

Cada especialista de carta tiene un único recurso modificable. Sus dependencias
son de solo lectura: Presentaciones consulta categorías y menajes; Subproductos
consulta productos; Recetas consulta presentaciones, productos y subproductos.
Si falta un requisito y el usuario desea crearlo, `solicitar_especialista` devuelve
al Coordinador una petición estructurada con recurso, instrucción y motivo. El runtime limita los
recursos tanto en los esquemas de herramientas como al ejecutar las llamadas.
Estas restricciones se suman a los permisos de la sesión y no los amplían.

`orchestrator/communication.py` conserva una pila de tareas mediante una continuación
firmada, con vigencia de dos horas y ligada a usuario, perfil y local. Solo delega
dependencias declaradas; limita la profundidad y rechaza ciclos. Abre el formulario
del requisito o invoca al especialista cuando requiere conversación. El chat muestra
los traspasos y la tarea pendiente. Las consultas simples conservan sus atajos de formulario.
Los pedidos que mencionan requisitos faltantes pasan por el especialista.

Cada borrador dependiente queda ligado al paso firmado. Tras `/realizar`, `/continuar`
verifica en el almacenamiento que ese mismo borrador fue REALIZADO y entrega su
resultado real al especialista padre. Soporta requisitos anidados y vuelve primero
al padre inmediato. No acepta resultados de creación enviados por el navegador.
Si falla retomar tras guardar, la interfaz ofrece reintentar solo la continuación;
no vuelve a ejecutar el cambio. Nueva consulta descarta la tarea pendiente.

La tarea original, las aclaraciones recientes y los resultados confirmados se
conservan por separado en la continuación firmada. El historial enviado por el
navegador no sustituye los identificadores devueltos por los módulos nativos.
Después de regresar al agente principal se mantiene la continuación mientras
recoge los datos faltantes. `tarea_pendiente` indica si todavía debe regresar a
otro agente: confirmar el borrador final termina el flujo sin llamar `/continuar`.
Promociones consulta las presentaciones existentes y solo prepara cambios en
promociones: precio, horario y grupos de opciones. Ya no pertenece al agente de insumos.

Los especialistas no escriben directamente en la base. `preparar_cambio` pasa por la validación existente, produce un borrador y exige confirmación explícita en `/realizar`. El backend vuelve a validar permisos, local y vigencia antes de ejecutar por las rutas nativas con auditoría.

Los pedidos de Salón no se exponen todavía como herramientas del asistente: usan una sesión separada y autorización PIN para acciones de responsable. No se debe reutilizar el token operativo del asistente para saltarse ese control.

En Permisos de agentes, Conexiones y permisos permite agregar consultas a módulos
del registro interno de herramientas, además de quitar o deshabilitar las asignadas.
Las conexiones nuevas se activan solo con Guardar permisos y llegan al runtime del
especialista, siempre cruzadas con el perfil y local activos. Los valores iniciales
conservan sus recursos nativos; ampliar el catálogo no activa accesos automáticamente.
La escritura continúa limitada a las acciones nativas de cada especialista y requiere
la revisión humana existente. Coordinador y Eventos usan flujos dedicados y no ofrecen
conexiones genéricas. APIs externas o campos no expuestos requieren implementar una
integración; editar la skill o marcar permisos no los conecta.
