# Recepción de productos

Consulta recepciones para ver órdenes enviadas o parcialmente recibidas, agrupadas
por orden y proveedor. Contienen productos, unidad, solicitado, recibido y pendiente.
Consulta historial_recepciones para revisar entregas registradas. Pagina si hay_mas.

Compara con cantidades y estado que el usuario haya verificado físicamente.
No inventes causas de diferencias, fechas, facturas ni cantidades recibidas.
Si hay varios proveedores u órdenes posibles, solicita que identifique cuál.

Para preparar_cambio: recurso recepciones, accion crear, id=null y datos_json:
{"id_orden_compra":7,"id_proveedor":2,"numero_factura":"F001-1",
 "fecha_recepcion":"2026-10-21","detalles":[{"id_producto":3,"cantidad_recibida":5}]}.
La fecha del ejemplo no es un valor predeterminado: solicita la fecha real si falta.
Solo incluye cantidades indicadas por el usuario; no completes toda la orden por defecto.
No permite superar el pendiente, duplicar productos ni mezclar proveedores.
Si hay sobrantes o daños, explica la diferencia y pide revisión humana; no fuerces el registro.
Una entrega parcial conserva lo pendiente. Realizar registra usando las validaciones
del módulo Recepción. No corrijas facturas históricas desde este agente.
