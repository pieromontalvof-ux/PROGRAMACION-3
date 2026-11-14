# Historial ficticio local de Sheraton

Autorización: el usuario solicita generar varios días y pedidos si la sede carece
de stock. Se comprobó conexión loopback, 141 saldos cero, sin cobros ni compras.

Carga aplicada con scripts/demo_sheraton.py: 21 días del 21/10 al 10/11/2026,
42 pedidos de salón y cobros, tres órdenes recibidas, 15 recepciones de proveedor,
11 presentaciones existentes y consumo real de sus recetas sobre 15 insumos.
Todos los comprobantes, movimientos y auditoría llevan DEMO-SHERATON-20261111.
No hay documentos fiscales ni envíos externos. Se mantiene respaldo local en
backend/instance/migration_backups/DEMO-SHERATON-20261111 y manifiesto de IDs.

Validación: una transacción, saldo final conciliado con recepciones menos ventas,
sin negativos, otras sedes sin cambios. API con rol Gerente/local4 devuelve HTTP200
en stock (15 productos con existencias), demanda (11 artículos vendidos, 15 insumos
consumidos) y pedido sugerido (11 insumos). La repetición rechaza duplicar el lote.
Revisión independiente detectó redondeo por agrupación; plan corregido para usar
exactamente los dos grupos de consumo por día que registra el script.

También corregida la fecha natural «miércoles de la próxima semana» con prueba
de regresión; prompt de eventos evita pedir datos internos que consultan otros
especialistas. Siete pruebas de períodos/conversación y 58 de compras pasan.
