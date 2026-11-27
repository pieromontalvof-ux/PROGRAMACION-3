"""Supplier invoice amounts, independent of inventory and tax issuance."""
from datetime import date
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
import re

from sqlalchemy import func, select

from app.core.extensions import db


def limites_comerciales():
    return db.session.execute(select(func.public.proveedor_limites_comerciales())).scalar_one()


def validar_comercial(datos):
    if not isinstance(datos, dict):
        raise ValueError('Completa los datos comerciales del proveedor.')
    resultado = {}
    for campo, limite in limites_comerciales().items():
        valor = datos.get(campo, '')
        if not isinstance(valor, str) or len(valor.strip()) > limite:
            raise ValueError(f'Revisa el campo {campo}.')
        resultado[campo] = valor.strip()
    if resultado['ruc'] and not re.fullmatch(r'[0-9]{11}', resultado['ruc']):
        raise ValueError('El RUC debe tener 11 dígitos.')
    if resultado['email'] and not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', resultado['email']):
        raise ValueError('Ingresa un correo válido.')
    return resultado


def numero(valor, nombre, positivo=False, decimales=3):
    try:
        n = Decimal(str(valor))
        if (not n.is_finite() or n < 0 or n > Decimal('999999999')
                or (positivo and n == 0) or n.as_tuple().exponent < -decimales):
            raise ValueError()
        return n
    except (InvalidOperation, TypeError, ValueError):
        raise ValueError(f'Revisa {nombre}: ingresa un número válido con hasta {decimales} decimales.') from None


def calcular_factura(datos):
    if not isinstance(datos, dict):
        raise ValueError('Completa los datos de la factura.')
    try:
        fecha = date.fromisoformat(datos.get('fecha_emision', ''))
    except (ValueError, TypeError):
        raise ValueError('Ingresa la fecha de emisión de la factura.') from None
    moneda = datos.get('moneda', 'PEN')
    if moneda not in ('PEN', 'USD'):
        raise ValueError('Selecciona soles o dólares.')
    lineas = datos.get('lineas')
    if not isinstance(lineas, list) or not 1 <= len(lineas) <= 500:
        raise ValueError('Registra entre 1 y 500 productos facturados.')
    total_base = Decimal(0); total_igv = Decimal(0); resultado = []; ids = set()
    bases = {tipo: Decimal(0) for tipo in ('GRAVADO', 'EXONERADO', 'INAFECTO', 'SIN_CLASIFICAR')}
    centimos = Decimal('.01')
    redondear = lambda n: n.quantize(centimos, rounding=ROUND_HALF_UP)
    for linea in lineas:
        if not isinstance(linea, dict) or type(linea.get('id_producto')) is not int or linea['id_producto'] <= 0:
            raise ValueError('Producto facturado inválido.')
        identidad = linea['id_producto']
        if identidad in ids:
            raise ValueError('Hay productos repetidos en la factura.')
        ids.add(identidad)
        cantidad = numero(linea.get('cantidad_facturada'), 'cantidad facturada', True)
        precio = numero(linea.get('precio_unitario', 0), 'precio unitario', decimales=6)
        descuento = numero(linea.get('descuento', 0), 'descuento', decimales=2)
        tasa = numero(linea.get('igv_porcentaje', (18 if linea.get('afectacion_igv','GRAVADO') == 'GRAVADO' else 0) if 'costo_total' in linea else 0), 'porcentaje de IGV', decimales=2)
        tipo = linea.get('afectacion_igv', 'GRAVADO' if tasa else 'SIN_CLASIFICAR')
        if tipo not in bases or (tipo == 'SIN_CLASIFICAR' and 'afectacion_igv' in linea):
            raise ValueError('Selecciona gravado, exonerado o inafecto para cada producto.')
        if (tipo == 'GRAVADO' and tasa == 0) or (tipo != 'GRAVADO' and tasa != 0):
            raise ValueError('Los productos exonerados e inafectos tienen IGV 0%; los gravados requieren una tasa mayor que cero.')
        bruto = redondear(cantidad * precio)
        if descuento > bruto or tasa > 100:
            raise ValueError('El descuento supera el importe o el impuesto supera el 100%.')
        base = bruto - descuento; impuesto = redondear(base * tasa / 100)
        if 'costo_total' in linea:
            if descuento: raise ValueError('El costo total ya debe incluir cualquier descuento de la factura.')
            total_linea = numero(linea['costo_total'], 'costo total', decimales=2)
            base = redondear(total_linea / (1 + tasa / 100))
            impuesto = total_linea - base
            precio = (base / cantidad).quantize(Decimal('.000001'), rounding=ROUND_HALF_UP)
        if base + impuesto > Decimal('999999999.99'):
            raise ValueError('El importe de la línea es demasiado grande.')
        total_base += base; total_igv += impuesto
        bases[tipo] += base
        resultado.append({'id_producto': identidad, 'cantidad_facturada': float(cantidad),
                          'precio_unitario': float(precio), 'descuento': float(descuento),
                          'afectacion_igv': tipo, 'igv_porcentaje': float(tasa), 'subtotal': float(base),
                          'igv': float(impuesto), 'total': float(base + impuesto)})
    return {'fecha_emision': fecha.isoformat(), 'moneda': moneda, 'lineas': resultado,
            'subtotal': float(total_base), 'igv': float(total_igv), 'total': float(total_base + total_igv),
            'base_gravada': float(bases['GRAVADO']), 'base_exonerada': float(bases['EXONERADO']),
            'base_inafecta': float(bases['INAFECTO']), 'base_sin_clasificar': float(bases['SIN_CLASIFICAR'])}
