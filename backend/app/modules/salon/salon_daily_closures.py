from sqlalchemy import bindparam, func, select

from app.core.extensions import db


def listar_cierres_diarios(id_local, desde, fin_exclusivo):
    if not db.session.execute(select(func.public.salon_cierres_instalados())).scalar():
        return []

    filas = db.session.execute(select(func.public.salon_cierres_diarios(bindparam('local'), bindparam('desde'), bindparam('fin')).table_valued(
        'fecha', 'simulacion', 'cantidad', 'efectivo', 'tarjeta',
    )), {'local': id_local, 'desde': desde, 'fin': fin_exclusivo}).mappings()
    return [
        {
            'fecha': fila['fecha'].isoformat(),
            'simulacion': fila['simulacion'],
            'cantidad': fila['cantidad'],
            'efectivo': float(fila['efectivo']),
            'tarjeta': float(fila['tarjeta']),
            'total': float(fila['efectivo'] + fila['tarjeta']),
        }
        for fila in filas
    ]
