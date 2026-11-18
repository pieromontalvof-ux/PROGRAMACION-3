"""Compact chat tables without changing source quantities or formulas."""
from decimal import Decimal, InvalidOperation
import re

UNITS={'KGM':'kg','LTR':'L','C62':'unidades'}


def number(value, places=3):
    try:
        amount=Decimal(str(value))
        if not amount.is_finite():
            return '—'
        return format(amount.quantize(Decimal(1).scaleb(-places)).normalize(),'f')
    except (InvalidOperation,TypeError,ValueError):
        return '—'


def cell(value):
    return re.sub(r'[\r\n|]+',' ',str(value if value is not None else '—'))


def quantity(value,unit):
    return number(value)+' '+UNITS.get(unit,unit or '')


def table(headers,rows):
    return '\n'.join(['| '+' | '.join(headers)+' |','| '+' | '.join('---' for _ in headers)+' |']+
                     ['| '+' | '.join(cell(v) for v in row)+' |' for row in rows])


def sales(items):
    return table(['Producto','Cantidad vendida','Promedio por día'],
                 [[r.get('nombre'),number(r.get('cantidad')),number(r.get('ventas_diarias'),2)] for r in items])
