"""Tableware dimensions and deterministic volume conversion, separate from stock units.

US/Imperial fluid ounces are distinct from weight ounces (NIST SP 811, B.9).
"""
from decimal import Decimal, InvalidOperation

from flask import g, has_request_context
from sqlalchemy import func, select

from app.core.extensions import db


def _leer_unidades_capacidad():
    return [dict(fila) for fila in db.session.execute(select(func.public.catalogo_capacidad_menaje().table_valued('codigo', 'nombre', 'factor', 'visible', 'alias'))).mappings()]


def unidades_capacidad():
    if not has_request_context():
        return _leer_unidades_capacidad()
    if "unidades_capacidad" not in g:
        g.unidades_capacidad = _leer_unidades_capacidad()
    return g.unidades_capacidad


def unidad_capacidad(unit):
    key = str(unit).upper()
    return next((row for row in unidades_capacidad() if key in (row['codigo'], row['alias'])), None)


FIELDS=('capacidad','unidad_capacidad','diametro_cm','altura_cm','largo_cm','ancho_cm')
def listar_medidas_menaje(id_menaje=None):
    filas = func.public.carta_medidas_menaje(id_menaje).table_valued(
        'id_menaje', 'nombre', 'activo', 'capacidad', 'unidad_capacidad',
        'diametro_cm', 'altura_cm', 'largo_cm', 'ancho_cm', 'origen_medidas',
    )
    return [dict(fila) for fila in db.session.execute(select(filas).order_by(filas.c.nombre)).mappings()]


def obtener_menaje_con_bloqueo(id_menaje, edicion=False):
    bloqueado = db.session.execute(select(func.public.carta_bloquear_menaje(id_menaje, edicion))).scalar()
    return listar_medidas_menaje(id_menaje) if bloqueado else []


def _reglas_medidas():
    filas = func.public.carta_reglas_medidas_menaje().table_valued(
        'campo', 'etiqueta', 'maximo', 'decimales',
    )
    return {fila['campo']: fila for fila in db.session.execute(select(filas)).mappings()}


def number(value, regla):
    etiqueta = regla['etiqueta']
    decimales = regla['decimales']
    try:
        result = Decimal(str(value))
        if (not result.is_finite() or result <= 0 or result > regla['maximo']
                or result != result.quantize(Decimal(1).scaleb(-decimales))):
            raise InvalidOperation
        return result
    except (InvalidOperation, ValueError, TypeError):
        raise ValueError(
            f'{etiqueta}: indica un valor positivo de hasta {regla["maximo"]} '
            f'y {decimales} decimales.'
        ) from None


def milliliters(value, unit):
    medida = unidad_capacidad(unit)
    if medida is None:
        raise ValueError('Selecciona una unidad de capacidad válida.')
    return Decimal(str(value)) * medida['factor']


def validated(data,previous=None):
    if set(data)-{'nombre',*FIELDS}:
        raise ValueError('El menaje contiene campos no permitidos.')
    result={key:data.get(key,(previous or {}).get(key)) for key in FIELDS}
    capacity,unit=result['capacidad'],result['unidad_capacidad']
    if (capacity is None)!=(unit is None):
        raise ValueError('Indica la capacidad y su unidad, o deja ambas sin registrar.')
    if capacity is not None:
        medida = unidad_capacidad(unit)
        if medida is None:
            raise ValueError('Selecciona una unidad de capacidad válida; distingue onzas líquidas de peso.')
        result['unidad_capacidad'] = medida['codigo']
    anterior = previous or {}
    pendientes = [
        campo for campo in FIELDS
        if campo != 'unidad_capacidad' and result[campo] is not None
        and (result[campo] != anterior.get(campo)
             or (campo == 'capacidad' and result['unidad_capacidad'] != anterior.get('unidad_capacidad')))
    ]
    if pendientes:
        reglas = _reglas_medidas()
        for campo in pendientes:
            if campo not in reglas:
                raise ValueError(f'No hay una regla de medida configurada para {campo}.')
            result[campo] = number(result[campo], reglas[campo])
    return result


def serialize(row):
    result=dict(row)
    for key in FIELDS:
        value=row.get(key)
        result[key]=float(value) if key!='unidad_capacidad' and value is not None else value
    result['capacidad_ml']=float(milliliters(row['capacidad'],row['unidad_capacidad'])) if row.get('capacidad') is not None and row.get('unidad_capacidad') else None
    return result


def ensure_fits(ware,content,unit):
    if ware.get('capacidad') is None or unidad_capacidad(unit) is None:
        return
    if milliliters(content,unit)>milliliters(ware['capacidad'],ware.get('unidad_capacidad')):
        raise ValueError('El contenido supera la capacidad registrada del menaje. Ajusta la medida o elige un recipiente mayor.')
