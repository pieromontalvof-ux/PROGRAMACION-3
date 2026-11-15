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
