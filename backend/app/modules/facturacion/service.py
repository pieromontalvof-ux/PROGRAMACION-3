"""Source snapshots are enqueued inside the caller's transaction."""
from sqlalchemy import text
from app.core.extensions import db
from . import repository as repo
from .contract import venta, compra


def enqueue_source(origin, source, local):
    if not repo.installed():
        return None
    config = db.session.execute(text('SELECT * FROM fact_api_config WHERE id_local=:local AND activo'),
                                {'local':local}).mappings().first()
    if not config:
        return None
    if origin=='VENTA':
        # Same row lock as corrections/annulments: a late manual enqueue cannot
        # supersede a newer source snapshot or resurrect a voided sale.
        row = db.session.execute(text('SELECT * FROM salon_cobro WHERE id_cobro=:id AND id_local=:local FOR UPDATE'),
                                 {'id':source,'local':local}).mappings().first()
        if not row or row['comprobante'].get('anulacion'):
            raise ValueError('Venta no disponible para generar documento.')
        payload = venta(row, config)
    elif origin=='COMPRA':
        row = db.session.execute(text('''SELECT f.*,o.id_local,o.codigo AS codigo_orden
            FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra)
            WHERE f.id_factura_recepcion=:id AND o.id_local=:local FOR UPDATE OF f'''),{'id':source,'local':local}).mappings().first()
        if not row:
            raise ValueError('Factura no encontrada en este local.')
        if not row['datos_factura']:
            return None  # Legacy receipts have no commercial amounts; never invent them.
        payload = compra(row, config)
    else:
        raise ValueError('Origen no válido.')
    return repo.enqueue(local, origin, source, payload)


def invalidate_sale(source,local):
    if not repo.installed():return
    db.session.execute(text('''UPDATE fact_api_operacion SET obsoleto=true,
        estado=CASE WHEN estado='COMPLETADO' THEN estado ELSE 'BLOQUEADO' END,
        lease_token=NULL,lease_hasta=NULL,ultimo_error='Venta interna anulada; documento histórico',
        actualizado_en=now() WHERE origen='VENTA' AND id_origen=:id AND id_local=:local'''),
        {'id':source,'local':local})
    db.session.execute(text('''UPDATE fact_api_intento i SET fin=now(),resultado='FUENTE_ANULADA'
        FROM fact_api_operacion o WHERE i.id_operacion=o.id_operacion AND i.fin IS NULL
        AND o.origen='VENTA' AND o.id_origen=:id AND o.id_local=:local AND o.obsoleto'''),
        {'id':source,'local':local})
