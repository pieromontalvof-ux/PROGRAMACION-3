# Barbarito

Aplicación de gestión de Barbarian: usuarios, catálogos, carta, inventario, movimientos, compras, recepción, salón y asistentes especializados.

- Frontend: React y TypeScript.
- Backend: Flask y SQLAlchemy.
- Base de datos: PostgreSQL 18.
- Despliegue: Docker con React y API bajo el mismo dominio, PostgreSQL separado y volumen persistente para los documentos de agentes.

La configuración y los pasos para Railway están en [DEPLOY.md](DEPLOY.md).

Los secretos se configuran mediante variables de entorno. Los archivos .env, respaldos, bases locales y documentos privados no se publican. database/schema.sql contiene solo la estructura, sin usuarios ni datos comerciales. Los datos existentes se migran por un canal privado.

Para desarrollo local, usar backend/.env.example, instalar backend/requirements.txt y ejecutar python run.py desde backend. En frontend, ejecutar npm ci y npm run dev; su .env.example apunta a la API local.
-

## Estructura

- `backend/app/core/`: configuración y servicios comunes del programa.
- `backend/app/modules/`: lógica y API del negocio: salón, cobros, inventario, compras, recepción y catálogos.
- `backend/app/multiagente/agents/`: coordinador, especialistas, actividad y conexiones.
- `backend/app/multiagente/api/`: API del asistente, herramientas, skills y confirmación de propuestas. Consulta las rutas del negocio; no sustituye sus reglas ni permisos.
- `frontend/src/`: interfaz; el asistente y su mapa están separados en `features/asistenteIA/`.
- `database/`: esquema y migraciones. `backend/tests/` y las pruebas del frontend verifican el funcionamiento.

Los informes de trabajo, exportaciones de base y respaldos locales no forman parte del código necesario. La configuración y los documentos editables de agentes permanecen en `backend/instance/agent_library/`; no se publican. `INICIAR_BARBARITO.bat` inicia el entorno local configurado, sin restaurar ni reemplazar bases de datos.

## Convenciones y diagnóstico

Es una aplicación web: no usa Activity, Fragment ni BaseActivity de Android. Las pantallas React usan `PascalCase` y el sufijo `Page`; los componentes, `PascalCase`; los hooks, `use...`; los servicios, `...Service.ts`; y los tipos compartidos se declaran en `types`. En Python se usa `snake_case` para módulos y funciones. Cada módulo de negocio conserva sus rutas, reglas y consultas; salón pertenece a `modules/salon`, autenticación a `modules/auth`. Los agentes permanecen en `multiagente`.

Las pantallas se cargan bajo demanda. `AppErrorBoundary` contiene errores de renderizado y permite reintentar o recargar la aplicación. `features/products/useProducts` separa la carga del catálogo de su presentación y cancela solicitudes obsoletas al cambiar de sesión o salir de la pantalla.

La API registra método, ruta normalizada, estado y duración, con un identificador generado por el servidor en `X-Request-ID`; `Server-Timing` muestra la duración. Estos registros no incluyen cuerpos, credenciales, documentos ni parámetros de búsqueda. Son mediciones HTTP, no un servicio externo de monitoreo ni una auditoría de negocio.

El administrador encuentra **Diagnóstico del sistema** en el menú de usuario (`/home/diagnostico`). El backend vuelve a validar el perfil activo y su permiso de consulta; no basta con abrir la dirección. Muestra solicitudes, errores de servidor y latencia p95 por ruta normalizada. Conserva hasta 500 muestras durante 15 minutos en memoria de cada proceso; no es un histórico persistente ni consolida varios servidores.

`hooks/useScopedCatalog` comparte la carga de usuarios y proveedores y descarta respuestas de sesiones o solicitudes anteriores. `services/salonService` contiene el transporte del salón, separado del diálogo de autorización. Las conversiones del formulario, el resumen de promociones y los cálculos de factura tienen módulos propios. `utils/scheduleEffect` permite cancelar el inicio de una carga si React desmonta su efecto antes de la microtarea, y ejecuta su limpieza al salir; no sustituye el `AbortController` de cada recurso.

Para comprobar asignaciones Python: ejecutar `python scripts/profile_http_memory.py` desde `backend`. Calienta 500 lecturas y mide otras 900 de `/api/health`, sin modificar datos, comprobando también el límite de muestras. Para Chrome: iniciar Vite en un puerto libre y ejecutar `node scripts/profile-browser-memory.mjs http://127.0.0.1:PUERTO` desde `frontend`. Usa un perfil temporal propio y recorre ingreso y acceso a salón; guarda las mediciones en `.local/browser-memory.json`. Estas muestras no acreditan ausencia de fugas en flujos autenticados ni miden toda la memoria del sistema.
# Integración fact_api de pruebas

Guía de operación, recorrido archivo por archivo y consultas PostgreSQL:
[docs/FACT_API_GUIA_OPERATIVA.md](docs/FACT_API_GUIA_OPERATIVA.md).
El servicio está separado en `services/fact_api`. Genera PDF de prueba para ventas
y vistas internas de facturas recibidas; no envía comprobantes a SUNAT.
