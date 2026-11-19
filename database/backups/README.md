# Respaldo completo cifrado

`barbarito-completo-2026-11-18.dump.enc` contiene la estructura y todos los datos de la base local al crear la copia. No incluye roles ni privilegios del servidor PostgreSQL. No se actualiza automaticamente con nuevas ventas.

La clave esta exclusivamente en `.local/database-backup.key` del equipo original y no se publica. Guarda otra copia de esa clave en un lugar privado: sin ella no es posible recuperar este respaldo.

## Recuperacion

1. Instalar Python y `pip install cryptography`.
2. Desde la raiz del proyecto, descifrar hacia un archivo local ignorado por Git:

```powershell
python database/backups/descifrar.py database/backups/barbarito-completo-2026-11-18.dump.enc --clave .local/database-backup.key --salida .local/barbarito-restaurar.dump
```

3. Crear una base vacia en PostgreSQL 18 y restaurar con un usuario autorizado:

```powershell
createdb -h 127.0.0.1 -U postgres barbarito_restaurado
pg_restore -h 127.0.0.1 -U postgres --dbname=barbarito_restaurado --no-owner --no-acl --exit-on-error .local/barbarito-restaurar.dump
```

Configura despues el usuario del programa y sus permisos. No restaures sobre la base activa sin revisar el destino. No subas a GitHub la clave ni el archivo descifrado.

`respaldo.json` contiene fecha, formato y SHA-256 del archivo cifrado. La copia paso una lectura completa de pg_restore y la comprobacion de descifrado byte a byte; no se ha restaurado sobre la base activa.
