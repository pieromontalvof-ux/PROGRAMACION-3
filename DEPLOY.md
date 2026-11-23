# Publicar Barbarito en Railway

El Dockerfile compila React con `VITE_API_URL=/api` y lo sirve junto con Flask mediante Gunicorn. Los usuarios acceden a un único dominio HTTPS. PostgreSQL es un servicio separado. El contenedor no incluye claves, datos del negocio, documentos subidos ni respaldos.

## Configuración

1. Crear un proyecto en Railway y añadir PostgreSQL **18**, compatible con la base actual. Comprobar la versión de la imagen; no restaurar un respaldo de PostgreSQL 18 en una versión anterior.
2. Añadir un servicio desde el repositorio de Barbarito, rama `main`, directorio raíz. Railway detecta el Dockerfile y `railway.json`.
3. En Variables del servicio de la aplicación, configurar:

| Variable | Valor |
|---|---|
| DATABASE_URL | Referencia a la URL privada del servicio PostgreSQL |
| SECRET_KEY | Secreto aleatorio propio de al menos 32 caracteres |
| JWT_SECRET_KEY | Otro secreto aleatorio de al menos 32 caracteres |
| OPENAI_API_KEY | Clave privada de OpenAI; solo en el backend |
| OPENAI_MODEL | Modelo autorizado en tu cuenta; por defecto gpt-6-luna |
| OPENAI_TRANSCRIPTION_MODEL | Por defecto gpt-4o-mini-transcribe |
| APP_DATA_DIR | /data |
| CORS_ORIGINS | Vacío: frontend y API comparten dominio |

Railway proporciona PORT. El servicio usa un proceso Gunicorn con cuatro hilos y una réplica; no ampliar réplicas sin compartir los límites de peticiones y validar la concurrencia.

4. Añadir un volumen persistente **al servicio de la aplicación**, montado en `/data`. PostgreSQL tiene su almacenamiento separado. Los archivos privados de agentes se guardan en `/data/agent_library`.
5. Migrar la base de datos **por un canal privado**, restaurando un respaldo actualizado y compatible con PostgreSQL 18. No subir ese respaldo a GitHub ni incorporarlo a la imagen. La aplicación no inicializa ni restaura datos automáticamente.
6. Para conservar las instrucciones, skills editadas y documentos actuales, transferir de forma privada el contenido de `backend/instance/agent_library/` a `/data/agent_library/`. No copiar estos archivos al repositorio. Los workspaces y demás datos guardados en PostgreSQL viajan con el respaldo de la base.
7. Generar el dominio público del servicio, comprobar `/api/health` y probar un inicio de sesión, una ruta interna al recargar y una consulta al asistente.

Los usuarios actuales se conservan al migrar la base, junto con sus contraseñas cifradas y perfiles. Una base vacía no tiene usuarios ni catálogos. `database/schema.sql` contiene solo la estructura actual: no reemplaza la migración privada de datos. Usar ese esquema únicamente para una base vacía; no ejecutarlo sobre una base restaurada.

## Integración de fact_api: configuración adicional pendiente en Railway

El Dockerfile actual publica el frontend React y el backend Flask. No incluye
PHP/Laravel ni arranca los trabajadores de facturación. Subir esta versión a
GitHub no instala automáticamente esos procesos en Railway.

Para habilitar allí los documentos se requiere preparar el servicio Laravel,
sus dependencias y base de datos, y un servicio trabajador con acceso al mismo
PostgreSQL y almacenamiento privado que utiliza Flask. Los scripts Windows de
inicio local no se ejecutan en Railway.

- Aplicar las migraciones correspondientes en las bases online, sin reemplazar
  datos existentes con el esquema completo ni con la base local de demostración.
- Configurar `FACT_API_URL` con la dirección del servicio accesible desde Railway;
  `127.0.0.1:8091` corresponde a la instalación local y no conecta otro servicio.
- Configurar los tokens privados en las variables de cada servicio. Para buscar
  DNI/RUC también se necesita `FACTILIZA_TOKEN` en el backend online.
- Mantener el modo DEMO, sin envío SUNAT ni credenciales fiscales reales.
- Compartir de forma segura el almacenamiento de entrega entre trabajador y
  Flask, y conservar el almacenamiento privado de Laravel. Los PDF locales no
  se transfieren mediante GitHub.
- Verificar cobro, cola, generación A4/ticket y descarga autenticada desde el
  dominio publicado antes de considerar completa la integración online.

La guía técnica y el recorrido de archivos están en
[docs/FACT_API_GUIA_OPERATIVA.md](docs/FACT_API_GUIA_OPERATIVA.md).

## Desarrollo local

Backend: crear un entorno Python, instalar `backend/requirements.txt`, copiar `backend/.env.example` a `.env` y completar los valores reales. Ejecutar `python run.py` desde backend. Gunicorn se usa en Linux/Docker; el servidor local de Flask sigue disponible en Windows.

Frontend: `npm ci` y `npm run dev` desde frontend. `frontend/.env.example` usa la API local; nunca colocar claves privadas en variables VITE_.

## Respaldos y actualizaciones

Configurar respaldos de PostgreSQL y del volumen de documentos. Una actualización del código no debe borrar ni reemplazar los volúmenes. Mantener `/data` fuera de la imagen y del repositorio. Si se cambia JWT_SECRET_KEY, las sesiones y validaciones firmadas anteriores dejan de servir.

Referencias oficiales: [Flask SPA](https://flask.palletsprojects.com/en/stable/patterns/singlepageapplications/), [Railway Docker](https://railway.com/guides/deploy-scale-docker-containers-railway), [volúmenes](https://docs.railway.com/volumes).
