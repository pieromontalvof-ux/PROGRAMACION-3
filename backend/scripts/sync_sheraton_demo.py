"""Complete the Sheraton demo in the configured local or Railway production database."""
import argparse
from datetime import date, timedelta
from pathlib import Path

from sqlalchemy import text

from app import create_app
from app.core.extensions import db
from app.modules.inventarios.weekly import report
from scripts.complete_sheraton_history import START, apply


def sync(through):
    result = apply(through, sync_demo=True)
    migration = Path(__file__).resolve().parents[2] / 'database/migrations/20261120_cierres_diarios_salon.sql'
    db.session.execute(text(migration.read_text(encoding='utf-8')))
    db.session.execute(text("""
        INSERT INTO salon_cierre_diario (id_local,fecha,simulacion,cantidad,efectivo,tarjeta)
        SELECT 4,j.fecha,true,count(c.id_cobro),
            coalesce(sum(c.total) FILTER (WHERE c.metodo='EFECTIVO'),0),
            coalesce(sum(c.total) FILTER (WHERE c.metodo='TARJETA'),0)
        FROM inventario_jornada j LEFT JOIN salon_cobro c
            ON c.id_local=j.id_local AND (c.creado_en AT TIME ZONE 'America/Lima')::date=j.fecha
            AND c.comprobante->'anulacion' IS NULL
        WHERE j.id_local=4 AND j.fecha BETWEEN :inicio AND :fin AND j.cerrado_en IS NOT NULL
        GROUP BY j.fecha
        ON CONFLICT (id_local,fecha) DO UPDATE
        SET cantidad=excluded.cantidad,efectivo=excluded.efectivo,tarjeta=excluded.tarjeta
        WHERE salon_cierre_diario.simulacion AND
            (salon_cierre_diario.cantidad,salon_cierre_diario.efectivo,salon_cierre_diario.tarjeta)
            IS DISTINCT FROM (excluded.cantidad,excluded.efectivo,excluded.tarjeta)
    """), {'inicio': START, 'fin': through})
    meta = report(4, today=through + timedelta(days=1))['metadata']
    if not meta['historial_completo'] or not meta['cobertura_completa']:
        raise RuntimeError('Cobertura incompleta: ' + str(meta['fechas_sin_registro']))
    return {
        'dias_cerrados': result['dias'],
        'jornadas_completadas': len(result['creados']),
        'ventas_nuevas': sum(item['cobros'] for item in result['creados']),
        'historial_completo': meta['historial_completo'],
        'cobertura_completa': meta['cobertura_completa'],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--through', type=date.fromisoformat, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    with create_app().app_context():
        result = sync(args.through)
        if args.apply:
            db.session.commit()
        else:
            db.session.rollback()
        print({'confirmado': args.apply, **result})


if __name__ == '__main__':
    main()
