# Asistente IA de Barbarito

## Pedido guiado

La solicitud "Quiero hacer un pedido" inicia el Coordinador de compras:
Eventos cercanos -> analisis opcionales -> consultas por chat -> porcentaje -> borrador.
Las opciones son un evento pasado parecido (la persona indica fechas), el movimiento
registrado desde la ultima orden enviada del local, y la cobertura del stock actual.
No existe un historial que vincule eventos y ventas: el analisis por fechas no implica causalidad.
Se puede revisar otro analisis, seguir preguntando o continuar directamente al pedido.

El Coordinador consulta Eventos una vez al iniciar; los reintentos son explicitos.
Eventos usa la direccion del local activo, los proximos siete dias y fuentes verificadas.
Un fallo no demuestra ausencia de eventos ni bloquea continuar al pedido.
Compras no busca eventos ni repite el analisis de demanda automaticamente.

El estado del flujo esta firmado, ligado al usuario/perfil/local y vence en dos horas.
Se conserva en el workspace. Las consultas durante la investigacion no tienen
herramientas de escritura. Una pregunta hipotetica sobre porcentajes no elige el margen.

Antes de preparar, el usuario elige porcentaje_general, sin un 20% fijo:
consumo * (1 + porcentaje / 100) - stock, redondeado por presentacion.
0% significa sin incremento. Los extras por producto son opcionales y no duplican el margen.
Realizar guarda un BORRADOR mediante la ruta nativa; el envio se revisa desde Compras.
Se conservan permisos, local, auditoria y proteccion contra confirmaciones duplicadas.
No requiere una migracion adicional.

Módulo conectado a OpenAI Responses y transcripción. La clave permanece en el backend. El modelo consulta herramientas autorizadas y propone un cambio; jamás ejecuta escrituras directamente.

## Organizacion
- routes.py: estado, preparar, realizar, cancelar y transcribir; sesión operativa vigente y límites de tamaño/frecuencia.
- provider.py: transporte HTTPS, errores sin secretos, tiempo máximo de 60 segundos por solicitud. OPENAI_MODEL por defecto gpt-6-luna; OPENAI_TRANSCRIPTION_MODEL por defecto gpt-4o-mini-transcribe. Ambos se pueden configurar en el entorno del backend. Sin dependencias nuevas.
- agent.py: ciclo limitado a siete respuestas del modelo; consultas paginadas, formularios y una propuesta por confirmación. store=false. Lee la skill en cada preparación.
- tools.py: lista cerrada de recursos y campos. Reutiliza las rutas Flask nativas con JWT, validaciones de negocio y auditoría. Para editar conserva campos no solicitados. No acepta SQL, rutas ni código del modelo.
- inventory.py y skills/inventario/SKILL.md: especialización de inventario en el mismo chat; consultas del local activo y propuestas confirmables para apertura, asignación por puesto y cierre de revisión.
- drafts.py: borradores ligados a usuario/perfil/local, vencimiento de 20 minutos, bloqueo al confirmar y comprobación de cambios posteriores. Confirmaciones exitosas repetidas devuelven el resultado registrado.
- skills/operaciones_catalogo/SKILL.md: procedimiento cargado en el contexto del modelo; no sustituye los controles del backend.
- test_routes.py y backend/tests/test_asistente_ia.py: pruebas de estado y de integración en PostgreSQL temporal.
- Frontend completo: frontend/src/features/asistenteIA/.

Consultas: productos, categorías de producto/carta, proveedores, presentaciones, menajes, subproductos, recetas, promociones y usuarios, según permisos. Usuarios: solo nombres, perfiles, puestos, locales y estado; sin DNI, correos, teléfonos, contraseñas ni PIN. Las consultas y las instrucciones sí se envían a OpenAI para responder. El audio solo se envía al transcriptor y no se guarda en el servidor.

Cambios: crear/editar los catálogos anteriores, excepto usuarios, solo con perfil administrador y permiso nativo. Los otros perfiles conservan la consulta autorizada. Crear receta requiere una presentación existente; crear artículo/presentación y receta son pasos separados, cada uno confirmado. El gerente también puede preparar apertura de conteos y asignación de varios productos por puesto. Gerente/supervisor pueden preparar guardar y cerrar una revisión completa con correcciones explícitas. Todas requieren Realizar; nunca cambian el stock.

Los puntos externos de conexión son el registro del blueprint, la ruta React y el enlace del menú. La opción es visible para perfiles autenticados de Gestión; no para tokens Salón. Stock, conteos, diferencias, asignaciones por puesto, jornadas y mix de ventas se consultan con permisos nativos del local activo. No modifica compras, recepciones, movimientos, stock ni salón, ni cierra jornadas. El administrador global debe cambiar a un perfil operativo autorizado para usar inventario.

## Activación
1. Configurar OPENAI_API_KEY en backend/.env (no versionar ni compartir).
2. Ejecutar manualmente database/migrations/20260923_asistente_ia.sql en barbarito. Sin ella funcionan consultas y dictado; no se pueden guardar propuestas de cambios.
3. Reiniciar backend y recargar frontend. Abrir Asistente IA desde Gestión.

## Persistencia y límites
La conversación editable es temporal y se elimina del navegador al salir/cambiar sesión. Los borradores y resultados de ejecución se conservan en PostgreSQL para evitar duplicados. No contienen claves ni audio. Si un proceso se interrumpe durante una escritura, el borrador puede quedar EJECUTANDO; no se repite automáticamente: revisar el registro y la auditoría antes de preparar otro. No existe ejecución automática de varios pasos ni transacción global entre ellos.

La limitación de ocho solicitudes por usuario/minuto es por proceso; un despliegue con varios workers necesita un limitador compartido o de proxy. El presupuesto de OpenAI debe administrarse también desde la cuenta/proyecto. El límite de audio es 15 MB, con grabación de hasta cinco minutos en la interfaz.

No se instala ningún paquete nuevo. La migración real se entrega para ejecución por el usuario.
La ampliación de inventario del 28/09/2026 no requiere SQL adicional sobre las migraciones existentes de asistente, jornadas y asignaciones por puesto.
Pruebas: desde backend, .venv/Scripts/python.exe -m unittest app.multiagente.api.test_routes -v
