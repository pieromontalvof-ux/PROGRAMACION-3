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

## Integración de fact_api dentro del servicio Railway

El Dockerfile incluye PHP 8.2, PHP-FPM, Nginx y las dependencias originales de
Laravel. `backend/scripts/cloud_runtime.py` conserva el inicio habitual de
Gunicorn si `FACT_API_BUNDLED` está desactivado. Para habilitar la integración:

| Variable del servicio MULTIAGENTE | Valor |
| --- | --- |
| FACT_API_BUNDLED | 1 |
| FACT_API_MODE | DEMO |
| FACT_API_MIN_WORKERS | 1 |
| FACT_API_MAX_WORKERS | 2, ampliable hasta 4 según recursos |
| RAILWAY_DEPLOYMENT_DRAINING_SECONDS | 90 |
| APP_DATA_DIR | /data, volumen persistente ya montado |

El arranque crea únicamente las tablas aditivas de clientes, cola y escalado que
falten y configura los locales activos. No restaura la base local ni borra ventas.
Laravel instala sus propias tablas en el esquema PostgreSQL `fact_api`, separado
de `public`. Ambas conexiones utilizan el PostgreSQL existente de Railway.

El puente escucha solo en `127.0.0.1:8091`, accesible desde los trabajadores del
mismo contenedor. Las rutas de setup y emisión SUNAT originales no se publican.
Flask sigue atendiendo el puerto público `PORT`; la web entrega los PDF únicamente
después de autenticar y comprobar el local. No se necesita otro dominio o servicio.

La clave Laravel y el token interno se generan una vez en
`/data/fact_api/runtime-secrets.json`, privado y excluido de Git. Al reiniciar se
reutilizan; un archivo corrupto detiene el arranque en vez de rotar las claves.
Los originales de Laravel quedan en `/data/fact_api/laravel_storage/app/private/`
y las copias operativas en `/data/fact_api_documents/`. Los PDF locales anteriores
no se transfieren mediante GitHub. El volumen conserva los generados online.

PHP-FPM utiliza como máximo dos procesos y el supervisor empieza con un trabajador,
ampliable automáticamente hasta el máximo configurado. Ante un redespliegue, el
supervisor nuevo espera el relevo del anterior sin detener el servidor web. El
arranque vigila sus procesos; una caída provoca reinicio y la cola permite recuperar
trabajos. La parada drena primero las peticiones web y después los trabajadores.

Para consultar DNI/RUC se configura `FACTILIZA_TOKEN` en Railway; es independiente
del generador. Toda esta integración sigue en DEMO: no envía documentos a SUNAT.

Después de habilitarla, comprobar `/api/health`, las métricas autenticadas, una
venta existente en el diario, PDF A4/ticket y persistencia tras un redespliegue.
Un cobro anterior sin operación puede generar su PDF desde el diario sin cobrar
nuevamente. No se hace una generación masiva de documentos históricos al arrancar.

La guía técnica y el recorrido de archivos están en
[docs/FACT_API_GUIA_OPERATIVA.md](docs/FACT_API_GUIA_OPERATIVA.md).

## Desarrollo local

Backend: crear un entorno Python, instalar `backend/requirements.txt`, copiar `backend/.env.example` a `.env` y completar los valores reales. Ejecutar `python run.py` desde backend. Gunicorn se usa en Linux/Docker; el servidor local de Flask sigue disponible en Windows.

Frontend: `npm ci` y `npm run dev` desde frontend. `frontend/.env.example` usa la API local; nunca colocar claves privadas en variables VITE_.

## Respaldos y actualizaciones

Configurar respaldos de PostgreSQL y del volumen de documentos. Una actualización del código no debe borrar ni reemplazar los volúmenes. Mantener `/data` fuera de la imagen y del repositorio. Si se cambia JWT_SECRET_KEY, las sesiones y validaciones firmadas anteriores dejan de servir.

Referencias oficiales: [Flask SPA](https://flask.palletsprojects.com/en/stable/patterns/singlepageapplications/), [Railway Docker](https://railway.com/guides/deploy-scale-docker-containers-railway), [volúmenes](https://docs.railway.com/volumes).
