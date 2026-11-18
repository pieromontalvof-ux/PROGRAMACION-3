"""Tableware dimensions and deterministic volume conversion, separate from stock units.

US/Imperial fluid ounces are distinct from weight ounces (NIST SP 811, B.9).
"""
from decimal import Decimal, InvalidOperation

FACTORS={'MLT':Decimal(1),'LTR':Decimal(1000),
         'FLOZ_US':Decimal('29.5735295625'),'FLOZ_UK':Decimal('28.4130625')}
FIELDS=('capacidad','unidad_capacidad','diametro_cm','altura_cm','largo_cm','ancho_cm')
SELECT_SQL='''SELECT m.*,d.capacidad,d.unidad_capacidad,d.diametro_cm,d.altura_cm,d.largo_cm,d.ancho_cm,d.origen_medidas
    FROM menaje m LEFT JOIN menaje_medida d USING(id_menaje)'''


def number(value,label):
    if isinstance(value,bool):
        raise ValueError(f'{label}: indica un número positivo.')
    try:
        result=Decimal(str(value))
        if not result.is_finite() or result<=0 or result>Decimal('1000000') or result!=result.quantize(Decimal('.001')):
            raise InvalidOperation
        return result
    except (InvalidOperation,ValueError,TypeError):
        raise ValueError(f'{label}: usa un valor positivo de hasta tres decimales.') from None


def milliliters(value,unit):
    key=str(unit).upper()
    key={'ML':'MLT','L':'LTR'}.get(key,key)
    if key not in FACTORS:
        raise ValueError('Elige mL, L, onzas líquidas estadounidenses o imperiales; oz de peso no mide capacidad.')
    return number(value,'Capacidad')*FACTORS[key]


def validated(data,previous=None):
    if set(data)-{'nombre',*FIELDS}:
        raise ValueError('El menaje contiene campos no permitidos.')
    result={key:data.get(key,(previous or {}).get(key)) for key in FIELDS}
    capacity,unit=result['capacidad'],result['unidad_capacidad']
    if (capacity is None)!=(unit is None):
        raise ValueError('Indica la capacidad y su unidad, o deja ambas sin registrar.')
    if capacity is not None:
        if unit not in FACTORS:
            raise ValueError('Selecciona una unidad de capacidad válida; distingue onzas líquidas de peso.')
        result['capacidad']=number(capacity,'Capacidad')
    for key in ('diametro_cm','altura_cm','largo_cm','ancho_cm'):
        if result[key] is not None:
            label={'diametro_cm':'Diámetro','altura_cm':'Altura','largo_cm':'Largo','ancho_cm':'Ancho'}[key]
            result[key]=number(result[key],label)
            if result[key]>10000:
                raise ValueError('Revisa las dimensiones en centímetros.')
    return result


def serialize(row):
    result=dict(row)
    for key in FIELDS:
        value=row.get(key)
        result[key]=float(value) if key!='unidad_capacidad' and value is not None else value
    result['capacidad_ml']=float(milliliters(row['capacidad'],row['unidad_capacidad'])) if row.get('capacidad') is not None and row.get('unidad_capacidad') else None
    return result


def ensure_fits(ware,content,unit):
    if str(unit).upper() not in ('MLT','ML','LTR','L') or ware.get('capacidad') is None:
        return
    if milliliters(content,unit)>milliliters(ware['capacidad'],ware.get('unidad_capacidad')):
        raise ValueError('El contenido supera la capacidad registrada del menaje. Ajusta la medida o elige un recipiente mayor.')
