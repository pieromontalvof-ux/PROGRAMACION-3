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
