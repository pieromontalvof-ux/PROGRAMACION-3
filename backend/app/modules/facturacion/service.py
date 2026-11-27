"""Source snapshots are enqueued inside the caller's transaction."""
from sqlalchemy import bindparam, func, select
from app.core.extensions import db
from . import repository as repo
from .contract import venta, compra


def enqueue_source(origin, source, local):
    if not repo.installed():
        return None
    config = db.session.execute(select(func.public.facturacion_configuracion_activa(bindparam('local')).table_valued(
        'id_local', 'activo', 'ambiente', 'empresa', 'serie_factura', 'serie_boleta',
        'tasa_igv', 'creado_en'
    )),
                                {'local':local}).mappings().first()
    if not config:
        return None
    if origin=='VENTA':
        # Same row lock as corrections/annulments: a late manual enqueue cannot
        # supersede a newer source snapshot or resurrect a voided sale.
        row = db.session.execute(select(func.public.facturacion_bloquear_venta(bindparam('id'), bindparam('local')).table_valued(
        'id_cobro', 'id_local', 'id_usuario', 'mesa', 'clave', 'solicitud_hash', 'tipo',
        'metodo', 'documento', 'cliente', 'total', 'comprobante', 'id_movimiento', 'creado_en',
        'id_jornada', 'id_cliente'
    )),
                                 {'id':source,'local':local}).mappings().first()
        if not row or row['comprobante'].get('anulacion'):
            raise ValueError('Venta no disponible para generar documento.')
        payload = venta(row, config)
    elif origin=='COMPRA':
        row = db.session.execute(select(func.public.facturacion_bloquear_compra(bindparam('id'), bindparam('local')).table_valued(
        'id_factura_recepcion', 'id_orden_compra', 'id_proveedor', 'numero_factura',
        'fecha_recepcion', 'usuario_recepcion', 'datos_factura', 'entregas', 'id_local',
        'codigo_orden'
    )),{'id':source,'local':local}).mappings().first()
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
    db.session.execute(select(func.public.facturacion_obsoletar_venta(bindparam('id'), bindparam('local'))),
        {'id':source,'local':local})
    db.session.execute(select(func.public.facturacion_cerrar_intentos_venta(bindparam('id'), bindparam('local'))),
        {'id':source,'local':local})
