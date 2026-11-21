from sqlalchemy import text

from app.core.extensions import db


def listar_cierres_diarios(id_local, desde, fin_exclusivo):
    if not db.session.execute(text(
        "SELECT to_regclass('public.salon_cierre_diario') IS NOT NULL"
    )).scalar():
        return []

    filas = db.session.execute(text("""
        SELECT fecha, simulacion, cantidad, efectivo, tarjeta
        FROM public.salon_cierre_diario
        WHERE id_local = :local AND fecha >= :desde AND fecha < :fin
        ORDER BY fecha DESC
    """), {'local': id_local, 'desde': desde, 'fin': fin_exclusivo}).mappings()
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
