"""PostgreSQL outbox and fenced leases; never holds a DB transaction during HTTP."""
import hashlib
import json
from uuid import uuid4
from sqlalchemy import Numeric, Uuid, bindparam, cast, func, select
from app.core.extensions import db


def installed():
    return db.session.execute(select(func.public.facturacion_instalado())).scalar() is True


def nombre_local(identidad):
    locales = func.public.usuarios_listar_locales().table_valued('id_local', 'nombre')
    return db.session.scalar(select(locales.c.nombre).where(locales.c.id_local == identidad))


def enqueue(local, origin, source, payload):
    encoded = json.dumps(payload, sort_keys=True, separators=(',',':'), ensure_ascii=False)
    digest = hashlib.sha256(encoded.encode()).hexdigest()
    # Serializes duplicate submissions and revisions of the same source.
    db.session.execute(select(func.public.facturacion_bloquear_fuente(bindparam('key'))), {'key': f'fact:{origin}:{source}'})
    previous = db.session.execute(select(func.public.facturacion_operacion_previa(bindparam('origin'), bindparam('source')).table_valued(
        'id_operacion', 'id_local', 'origen', 'id_origen', 'version', 'payload', 'payload_hash',
        'estado', 'intentos', 'disponible_en', 'lease_hasta', 'lease_token', 'ultimo_http',
        'ultimo_error', 'creado_en', 'actualizado_en', 'max_intentos', 'obsoleto'
    )),
        {'origin':origin,'source':source}).mappings().first()
    if previous and previous['payload_hash']==digest:
        return str(previous['id_operacion'])
    db.session.execute(select(func.public.facturacion_obsoletar_fuente(bindparam('origin'), bindparam('source'))),{'origin':origin,'source':source})
    db.session.execute(select(func.public.facturacion_cerrar_intentos_fuente(bindparam('origin'), bindparam('source'))),{'origin':origin,'source':source})
    identity = str(uuid4())
    db.session.execute(select(func.public.facturacion_encolar(cast(bindparam('id'), Uuid), bindparam('local'), bindparam('origin'), bindparam('source'), bindparam('version'), bindparam('payload'), bindparam('hash'))),
        {'id':identity,'local':local,'origin':origin,'source':source,'version':previous['version']+1 if previous else 1,
         'payload':encoded,'hash':digest})
    return identity


def claim():
    token = str(uuid4())
    row = db.session.execute(select(func.public.facturacion_reclamar(bindparam('token')).table_valued(
        'id_operacion', 'id_local', 'origen', 'id_origen', 'version', 'payload', 'payload_hash',
        'estado', 'intentos', 'disponible_en', 'lease_hasta', 'lease_token', 'ultimo_http',
        'ultimo_error', 'creado_en', 'actualizado_en', 'max_intentos', 'obsoleto'
    )), {'token':token}).mappings().first()
    # Exhausted workers that died are visible, never left permanently processing.
    db.session.execute(select(func.public.facturacion_revisar_agotadas()))
    db.session.execute(select(func.public.facturacion_cerrar_intentos_agotados()))
    if row:
        db.session.execute(select(func.public.facturacion_cerrar_intentos_operacion(cast(bindparam('id'), Uuid))), {'id':row['id_operacion']})
        db.session.execute(select(func.public.facturacion_abrir_intento(cast(bindparam('id'), Uuid), bindparam('number'))), {'id':row['id_operacion'],'number':row['intentos']})
    db.session.commit()
    return dict(row) if row else None


def finish(job, state, status, duration, error=None, delay=0, document=None, files=()):
    params = {'id':str(job['id_operacion']),'lease':str(job['lease_token']), 'state':state,
              'status':status,'duration':duration,'error':error,'delay':delay,'number':job['intentos']}
    owned = db.session.execute(select(func.public.facturacion_bloquear_procesada(cast(bindparam('id'), Uuid), cast(bindparam('lease'), Uuid))),params).scalar()
    if not owned:
        db.session.rollback()
        return False
    if document:
        doc_id = str(job['id_operacion'])
        db.session.execute(select(func.public.facturacion_guardar_documento(cast(bindparam('id'), Uuid), bindparam('local'), cast(bindparam('external'), Uuid), bindparam('numero'), cast(bindparam('subtotal'), Numeric), cast(bindparam('igv'), Numeric), cast(bindparam('total'), Numeric))),
            {**params,'local':job['id_local'],'external':document['id'], 'numero':document['numero'],
             'subtotal':job['payload']['subtotal'],'igv':job['payload']['igv'],'total':job['payload']['total']})
        for file in files:
            db.session.execute(select(func.public.facturacion_guardar_archivo(cast(bindparam('file'), Uuid), cast(bindparam('id'), Uuid), bindparam('format'), bindparam('path'), bindparam('hash'), bindparam('size'))),
                {'file':str(uuid4()),'id':doc_id,**file})
    db.session.execute(select(func.public.facturacion_finalizar_operacion(bindparam('state'), bindparam('status'), bindparam('error'), cast(bindparam('delay'), Numeric), cast(bindparam('id'), Uuid))),params)
    db.session.execute(select(func.public.facturacion_finalizar_intento(cast(bindparam('duration'), Numeric), bindparam('status'), bindparam('state'), cast(bindparam('id'), Uuid), bindparam('number'))),params)
    if status>=500 or status==429:
        db.session.execute(select(func.public.facturacion_registrar_fallo()))
    elif state=='COMPLETADO':
        db.session.execute(select(func.public.facturacion_reiniciar_circuito()))
    db.session.commit()
    return True
