# Respaldos completos cifrados

`respaldo.json` identifica la última generación verificada, con fecha, tamaños y
SHA-256. Incluye estructura y datos completos de `barbarito` y `fact_api_demo`,
además de un ZIP cifrado de sus PDF/XML/CDR privados existentes. Se conservan las
generaciones anteriores. No incluye roles, privilegios, archivos `.env`, certificados
ni la clave de cifrado. No se actualiza automáticamente con ventas posteriores.

La clave está exclusivamente en `.local/database-backup.key`. Guarda otra copia
en un lugar privado: sin ella no se pueden recuperar estos respaldos. No publicar
la clave ni los archivos descifrados.

## Crear y verificar

Se requieren Python, cryptography, python-dotenv, SQLAlchemy y PostgreSQL 18.
El script admite las dependencias privadas instaladas en `.local/backup-tools`.
Utiliza la conexión administrativa local del backend:

```powershell
backend/.venv/Scripts/python.exe database/backups/crear_respaldo.py --verify-restore
```

Prepara una generación única en `.local/backup-staging`, comprueba el descifrado,
lectura completa mediante pg_restore, integridad ZIP y escritura de archivos.
Con `--verify-restore` restaura cada base en una base temporal nueva y elimina
solamente esas bases temporales. Nunca restaura sobre las bases activas.
El manifiesto se publica atómicamente al final; un fallo no sustituye la generación
anterior conocida. Un bloqueo local evita ejecuciones simultáneas.

Los dumps son consistentes por separado. Para una copia coordinada de las dos
bases y archivos, cerrar ordenadamente el supervisor y pausar nuevas operaciones
mientras se crea el respaldo: no hay una transacción distribuida entre ellos.

## Recuperación

1. Revisar `respaldo.json` y elegir el archivo de base correspondiente.
2. Instalar cryptography si hace falta. Descifrar hacia `.local`:

```powershell
python database/backups/descifrar.py database/backups/NOMBRE.dump.enc --clave .local/database-backup.key --salida .local/restaurar.dump
```

3. Crear una base nueva y restaurar sin apuntar a la activa:

```powershell
createdb -h 127.0.0.1 -U postgres barbarito_restaurado
pg_restore -h 127.0.0.1 -U postgres --dbname=barbarito_restaurado --no-owner --no-acl --exit-on-error .local/restaurar.dump
```

Repetir para fact_api_demo con otro nombre de base y archivo. Configurar después
usuarios, permisos y conexiones privadas de cada servicio.

4. Descifrar el archivo `fact-api-documentos-....zip.enc` con el mismo programa,
usando una salida `.local/documentos-restaurar.zip`. Extraer en una carpeta nueva:

- `barbarito_documents/` corresponde a `backend/instance/fact_api_documents` o a
  la ubicación configurada en `FACT_API_DOCUMENTS_DIR`.
- `fact_api_private/` corresponde a `services/fact_api/storage/app/private/barbarito`.

Los esquemas sin datos están en `database/schema.sql` y `database/fact_api_schema.sql`.
Conservar por separado la configuración privada del servidor.
