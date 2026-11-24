# Semana de prueba completada: 17–23 noviembre de 2026

Se aplicó el lote `DEMO-SEMANA-VARIADA-20261117-23-V1` en la base local y en
Railway, con los mismos 482 cobros nuevos y conservando las ventas manuales
preexistentes de cada entorno.

| Local | Cobros nuevos | Efectivo | Tarjeta | Total nuevo |
|---|---:|---:|---:|---:|
| Miraflores | 121 | 47 | 74 | S/ 23 197,90 |
| Santa Anita | 118 | 41 | 77 | S/ 21 527,30 |
| Barranco | 123 | 52 | 71 | S/ 21 289,50 |
| Sheraton | 120 | 47 | 73 | S/ 22 220,30 |

Por local: siete jornadas y cierres de caja, 141 insumos en cada reporte,
tres días de recepción (17, 20 y 23), 30 facturas de proveedores y siete
movimientos de merma. Los tickets contienen cantidades y presentaciones distintas;
el consumo usa las recetas registradas. Se incluyen boletas simples, boletas
electrónicas y facturas **internas de prueba**, sin emisión fiscal.

La reposición incluye el consumo histórico que ya existía y un saldo de respaldo.
Las aperturas continúan el cierre anterior y los saldos finales concilian con los
movimientos y el stock actual. No se fuerza que cada entrada iguale la salida de
ese mismo día. Los cierres de caja suman exactamente las ventas no anuladas por
forma de pago.

Las jornadas anteriores que seguían abiertas sin pedidos pendientes se
regularizaron con sus reportes calculados y una entrada de auditoría. Los
vínculos derivados de jornada se corrigieron según las fechas de cobros y eventos;
no se modificaron importes, clientes ni líneas de las ventas manuales.

El pedido local de Barranco M01 se cobró mediante el endpoint normal del sistema,
por autorización expresa del usuario: S/ 125, boleta simple, efectivo. Ese cobro
conserva su fecha real del 24 de noviembre; no se retrocedió artificialmente al 23.

## Ejecución

```powershell
cd backend
.venv/Scripts/python.exe scripts/demo_varied_week.py
.venv/Scripts/python.exe scripts/demo_varied_week.py --validate --close-stale
.venv/Scripts/python.exe scripts/demo_varied_week.py --apply --close-stale
```

El primer comando solo inspecciona; el segundo ejecuta y revierte. El último
guarda una transacción completa después de verificar caja, inventarios y
preservación de ventas manuales. El marcador impide volver a duplicar la carga.
Se omiten locales con pedidos sin cobrar, conteos abiertos o cierres operativos
no simulados. `--close-stale` permite regularizar jornadas anteriores abiertas;
no se aplicará si hay pedidos pendientes.

Antes de modificar se guarda un resguardo privado de las filas afectadas en
`instance/history_backups/` (local) o `/data/history_backups/` (Railway), fuera
de Git y con permisos restringidos. La carga histórica no crea trabajos fact_api;
el cobro normal autorizado mantiene el funcionamiento habitual de Salón.

## Verificación en PostgreSQL

```sql
SELECT id_local, fecha, cerrado_en,
       jsonb_array_length(reporte->'inventario') AS insumos
FROM inventario_jornada
WHERE fecha BETWEEN '2026-11-17' AND '2026-11-23'
ORDER BY id_local, fecha;

SELECT id_local, fecha, cantidad, efectivo, tarjeta
FROM salon_cierre_diario
WHERE fecha BETWEEN '2026-11-17' AND '2026-11-23'
ORDER BY id_local, fecha;

SELECT id_local, metodo, count(*) AS cobros, sum(total) AS total
FROM salon_cobro
WHERE comprobante->>'prueba'='DEMO-SEMANA-VARIADA-20261117-23-V1'
GROUP BY id_local, metodo ORDER BY id_local, metodo;
```
