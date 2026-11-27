"""Immutable bridge payloads; prices in the POS include configured demo tax."""
from decimal import Decimal, ROUND_HALF_UP
from datetime import datetime, timezone, timedelta


def money(value):
    value = Decimal(str(value))
    if not value.is_finite() or value < 0:
        raise ValueError('Importe inválido para fact_api.')
    return value.quantize(Decimal('.01'), rounding=ROUND_HALF_UP)


def contacto_tercero(datos):
    return {
        campo: valor.strip()[:limite]
        for campo, limite in (('direccion', 255), ('email', 200), ('telefono', 40))
        if isinstance(valor := datos.get(campo), str) and valor.strip()
    }


def venta(row, config):
    moment=row['creado_en']
    if not isinstance(moment,datetime):
        moment=datetime.fromisoformat(str(moment).replace('Z','+00:00'))
    fecha=moment.astimezone(timezone(timedelta(hours=-5))).date() if moment.tzinfo else moment.date()
    tax = Decimal(str(config['tasa_igv']))
    lines = []
    for line in row['comprobante']['lineas']:
        qty = Decimal(str(line['cantidad']))
        if not qty.is_finite() or qty <= 0:
            raise ValueError('Cantidad inválida.')
        total = money(Decimal(str(line['precio'])) * qty)
        base = money(total / (1 + tax / 100))
        lines.append({'codigo': str(line.get('id_presentacion') or line.get('id_promocion') or len(lines)+1),
                      'nombre': str(line['nombre'])[:200], 'cantidad': str(qty), 'unidad': 'C62',
                      'subtotal': str(base), 'igv': str(total-base), 'total': str(total),
                      'tasa_igv': str(tax), 'afectacion': 'GRAVADO' if tax else 'INAFECTO'})
    total = sum((Decimal(l['total']) for l in lines), Decimal(0))
    if not lines or total != money(row['total']):
        raise ValueError('El detalle no coincide con el total del cobro.')
    return {'version': 1, 'origen': 'VENTA', 'referencia': str(row['id_cobro']), 'id_local': row['id_local'],
            'empresa': config['empresa'], 'tipo': '01' if row['tipo']=='FACTURA' else '03',
            'serie': config['serie_factura'] if row['tipo']=='FACTURA' else config['serie_boleta'],
            'fecha': fecha.isoformat(), 'moneda': 'PEN',
            'tercero': {'nombre': row.get('cliente') or 'Consumidor final',
                        'documento': row.get('documento') or '', 'tipo': '6' if row['tipo']=='FACTURA' else '1',
                        **contacto_tercero(row['comprobante'].get('contacto') or {})},
            'lineas': lines, 'subtotal': str(sum(Decimal(l['subtotal']) for l in lines)),
            'igv': str(sum(Decimal(l['igv']) for l in lines)), 'total': str(total)}


def compra(row, config):
    invoice = row['datos_factura']
    if not invoice or not invoice.get('lineas'):
        raise ValueError('La recepción necesita el detalle comercial de su factura.')
    provider = invoice['proveedor']
    return {'version': 1, 'origen': 'COMPRA', 'referencia': str(row['id_factura_recepcion']),
            'id_local': row['id_local'], 'empresa': config['empresa'], 'tipo': '01',
            'serie': row['numero_factura'].split('-')[0],
            'numero_proveedor': row['numero_factura'], 'orden_compra': row['codigo_orden'],
            'fecha': invoice['fecha_emision'], 'moneda': invoice['moneda'],
            'tercero': {'nombre': provider.get('razon_social') or provider['nombre'],
                        'documento': provider.get('ruc',''), 'direccion': provider.get('direccion',''), 'tipo':'6',
                        **contacto_tercero(provider)},
            'lineas': [{'codigo': str(l['id_producto']), 'nombre': l.get('nombre') or str(l['id_producto']),
                        'cantidad': str(l['cantidad_facturada']), 'unidad': l.get('unidad','C62'),
                        'subtotal': str(money(l['subtotal'])), 'igv': str(money(l['igv'])),
                        'total': str(money(l['total'])), 'tasa_igv': str(l['igv_porcentaje']),
                        'afectacion': l['afectacion_igv']} for l in invoice['lineas']],
            'subtotal': str(money(invoice['subtotal'])), 'igv': str(money(invoice['igv'])),
            'total': str(money(invoice['total']))}
