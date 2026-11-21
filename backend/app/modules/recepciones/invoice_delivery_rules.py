from collections.abc import Callable
from decimal import Decimal

from werkzeug.exceptions import BadRequest

from .invoices import numero


def validar_detalles_entrega(
    detalles,
    lineas_facturadas,
    detalles_recibidos,
    obtener_cantidad_pendiente: Callable[[int], Decimal | None],
):
    if not isinstance(detalles, list) or not detalles or len(detalles) > 500:
        raise BadRequest('Indica los productos entregados.')

    lineas = {linea['id_producto']: linea for linea in lineas_facturadas}
    actuales = {detalle['id_producto']: detalle for detalle in detalles_recibidos}
    vistos = set()
    validos = []
    for detalle in detalles:
        if not isinstance(detalle, dict) or type(detalle.get('id_producto')) is not int:
            raise BadRequest('Producto inválido.')
        identidad = detalle['id_producto']
        if identidad not in lineas or identidad in vistos:
            raise BadRequest('Producto ajeno o repetido.')
        vistos.add(identidad)

        cantidad = numero(detalle.get('cantidad_recibida'), 'cantidad recibida', True)
        actual = actuales.get(identidad)
        acumulado = (actual['cantidad_recibida'] if actual else Decimal(0)) + cantidad
        pendiente = obtener_cantidad_pendiente(identidad)
        if (
            acumulado > Decimal(str(lineas[identidad]['cantidad_facturada']))
            or pendiente is None
            or cantidad > pendiente
        ):
            raise BadRequest('La entrega supera lo pendiente de la factura o de la OC.')
        validos.append((identidad, cantidad, acumulado, actual))
    return validos
