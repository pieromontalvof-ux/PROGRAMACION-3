# Limites de stock estrictos

`20261021_limites_stock_estrictos.sql` requiere la tabla creada por
`20260922_limites_stock.sql`. Se ejecuta con `psql -v ON_ERROR_STOP=1 -f` tras
verificar la base de destino. La migracion es repetible y reemplaza de forma
atomica la restriccion anterior por `stock_maximo IS NULL OR stock_maximo >
stock_minimo`. El tiempo de espera por bloqueos es de 5 segundos; si vence,
la transaccion se revierte y debe reintentarse en un momento adecuado.

No cambia ningun dato. Conserva los maximos nulos y los limites historicos
iguales. La nueva restriccion se agrega como `NOT VALID`: comprueba todos los
INSERT y UPDATE nuevos, incluso una actualizacion de otra columna de una fila
historica que aun tenga limites iguales. Esas filas deben corregirse mediante
una decision explicita al editarlas. Si todas las filas existentes cumplen la
regla, la migracion valida la restriccion automaticamente; de lo contrario la
deja pendiente, pero ya activa para las nuevas escrituras.

Consulta de filas pendientes, sin modificarlas:

```sql
SELECT id_producto, id_local, stock_minimo, stock_maximo
FROM public.producto_stock_local
WHERE stock_maximo IS NOT NULL AND stock_maximo <= stock_minimo;
```

Despues de revisar y corregir deliberadamente esas filas, se puede validar:

```sql
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE public.producto_stock_local VALIDATE CONSTRAINT ck_stock_local_maximo;
COMMIT;
```

Prueba funcional aislada (PowerShell, desde `backend`), sin leer `.env`, copiar
datos ni conectar con una base existente:

```powershell
$env:STOCK_LIMITS_MIGRATION_TEST_DB = '1'
./.venv/Scripts/python.exe -m unittest discover -s tests -p test_stock_limits_migration.py -v
```

El test inicializa y detiene un cluster PostgreSQL temporal. `POSTGRES_BIN`
permite elegir el directorio de binarios; por defecto usa PostgreSQL 18 en
Windows. Comprueba conservacion historica, rechazo de escrituras futuras,
repeticion y validacion posterior.
