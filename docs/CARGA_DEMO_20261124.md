# Operación de prueba del 24 de noviembre de 2026

Carga realizada el 25 de noviembre en las bases local y Railway para todos los
locales activos. Los registros generados son datos de prueba, identificados con
`DEMO-OPERACION-VARIADA-20261124-20261124-V1`; no son comprobantes fiscales emitidos.

| Local | Ventas nuevas | Importe nuevo (S/) |
| --- | ---: | ---: |
| Miraflores | 15 | 2348.80 |
| Santa Anita | 18 | 3282.70 |
| Barranco | 13 | 2781.60 |
| Sheraton | 16 | 2649.40 |

Se añadieron consumos según recetas, recepciones, mermas, conteos de inventario
y cierres diarios de caja e inventario. Las ventas existentes se conservaron;
Barranco local conserva además una venta previa de S/125.00 de esa fecha.

La carga se validó primero con rollback y después se confirmó. Se comprobó la
conciliación entre aperturas, movimientos, cierres y stock posterior; los cierres
de caja coinciden con los cobros. No se crearon trabajos de facturación externa.
Cada base conserva un resguardo previo privado en `history_backups`.

El cargador admite períodos de uno a siete días, con modo plan por defecto:

```powershell
cd backend
.venv/Scripts/python.exe scripts/demo_varied_week.py --start 2026-11-24 --end 2026-11-24
```

`--validate` comprueba la carga y revierte; `--apply` guarda con resguardo previo.
La misma carga ya aplicada se omite para evitar duplicados. Los cierres operativos
ajenos a la simulación y las jornadas posteriores cerradas permanecen protegidos.

El manifiesto `database/backups/respaldo.json` identifica el respaldo completo
local actualizado que incluye esta carga. Sus archivos están cifrados; la clave
permanece fuera de Git. Esta copia local no debe confundirse con un volcado de
Railway, aunque la carga se verificó por separado en ambos entornos.
