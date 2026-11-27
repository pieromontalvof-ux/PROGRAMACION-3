"""Store-scoped status and private document downloads; no upstream token exposed."""
import hashlib
from pathlib import Path
from flask import Blueprint, jsonify, request, send_file
from sqlalchemy import Uuid, bindparam, cast, func, select
from werkzeug.exceptions import BadRequest, Conflict, NotFound
from app.core.extensions import db
from app.modules.clientes.routes import acceso
from .service import enqueue_source
from .repository import installed
from .worker import storage_root

fact_api_bp=Blueprint('fact_api',__name__)
salon_fact_api_bp=Blueprint('salon_fact_api',__name__)


def validate_origin(origin):
    if origin not in ('VENTA','COMPRA'):raise NotFound('Origen no disponible.')


@fact_api_bp.get('/<origin>/<int:source>')
@acceso
def status(local,origin,source):
    validate_origin(origin)
    if not installed():return jsonify(disponible=False,operaciones=[])
    rows=db.session.execute(select(func.public.facturacion_estado_fuente(bindparam('local'), bindparam('origin'), bindparam('source')).table_valued(
        'id_operacion', 'version', 'estado', 'intentos', 'ultimo_error', 'obsoleto',
        'creado_en', 'actualizado_en', 'id_documento', 'numero', 'estado_documento', 'archivos'
    )),
        {'local':local,'origin':origin,'source':source}).mappings().all()
    configured=db.session.execute(select(func.public.facturacion_local_configurado(bindparam('local'))),{'local':local}).scalar()
    attachments=[]
    if origin=='COMPRA':
        attachments=[dict(r) for r in db.session.execute(select(func.public.facturacion_originales_compra(bindparam('local'), bindparam('source')).table_valued(
        'id_adjunto', 'formato', 'creado_en'
    )),{'local':local,'source':source}).mappings()]
    return jsonify(disponible=bool(configured),modo='DEMO',operaciones=[dict(r) for r in rows],originales=attachments)


@fact_api_bp.post('/COMPRA/<int:source>/originales')
@acceso
def upload_original(local,source):
    request.max_content_length=6*1024*1024
    from .attachments import save_original
    available=db.session.execute(select(func.public.facturacion_compra_disponible(bindparam('id'), bindparam('local'))),{'id':source,'local':local}).scalar()
    if not available:raise NotFound('Factura no encontrada en este local.')
    file=request.files.get('archivo')
    kind=request.form.get('formato','')
    if not file:raise BadRequest('Adjunta el original del proveedor.')
    try:
        identity=save_original(local,source,file.read(5*1024*1024+1),kind)
        db.session.commit()
        return jsonify(id_adjunto=identity),201
    except ValueError as error:
        db.session.rollback();raise BadRequest(str(error)) from None
    except Exception:
        db.session.rollback();raise


@fact_api_bp.get('/originales/<uuid:identity>')
@acceso
def download_original(local,identity):
    row=db.session.execute(select(func.public.facturacion_original_por_local(cast(bindparam('id'), Uuid), bindparam('local')).table_valued(
        'id_adjunto', 'id_local', 'id_factura_recepcion', 'formato', 'ruta', 'sha256', 'bytes',
        'creado_en'
    )),
                           {'id':str(identity),'local':local}).mappings().first()
    if not row:raise NotFound('Original no encontrado en este local.')
    path=(storage_root()/row['ruta']).resolve()
    if not path.is_relative_to(storage_root()) or not path.is_file():raise NotFound('Original no disponible.')
    if hashlib.sha256(path.read_bytes()).hexdigest()!=row['sha256']:raise Conflict('Integridad del original no válida.')
    return send_file(path,as_attachment=True,download_name=f"original_{identity}.{row['formato'].lower()}",
                     mimetype='application/pdf' if row['formato']=='PDF' else 'application/xml')


@fact_api_bp.post('/<origin>/<int:source>')
@acceso
def enqueue(local,origin,source):
    validate_origin(origin)
    try:
        identity=enqueue_source(origin,source,local)
        if not identity:raise Conflict('Sin configuración o detalle comercial para generar documento.')
        db.session.commit()
        return jsonify(id_operacion=identity,modo='DEMO'),202
    except ValueError as error:
        db.session.rollback();raise BadRequest(str(error)) from None
    except Exception:
        db.session.rollback();raise


@fact_api_bp.post('/operaciones/<uuid:identity>/reintentar')
@acceso
def retry(local,identity):
    row=db.session.execute(select(func.public.facturacion_reencolar(cast(bindparam('id'), Uuid), bindparam('local'))),{'id':str(identity),'local':local}).scalar()
    # Keep monotonic attempt numbers; never delete historical attempts.
    if row:
        db.session.execute(select(func.public.facturacion_actualizar_intentos(cast(bindparam('id'), Uuid))),{'id':str(identity)})
    db.session.commit()
    if not row:raise Conflict('Operación no disponible para reintentar en este local.')
    return jsonify(id_operacion=str(row)),202


@fact_api_bp.get('/archivos/<uuid:identity>')
@acceso
def download(local,identity):
    row=db.session.execute(select(func.public.facturacion_archivo_por_local(cast(bindparam('id'), Uuid), bindparam('local')).table_valued(
        'id_archivo', 'id_documento', 'formato', 'ruta', 'sha256', 'bytes', 'creado_en'
    )),{'id':str(identity),'local':local}).mappings().first()
    if not row:raise NotFound('Archivo no encontrado en este local.')
    path=(storage_root()/row['ruta']).resolve()
    if not path.is_relative_to(storage_root()) or not path.is_file():raise NotFound('Archivo no disponible.')
    if hashlib.sha256(path.read_bytes()).hexdigest()!=row['sha256']:
        raise Conflict('La integridad del archivo no coincide. Revisa el respaldo.')
    response=send_file(path,mimetype='application/pdf',as_attachment=True,download_name=f"{row['id_documento']}_{row['formato']}.pdf")
    response.headers['Cache-Control']='private, no-store'
    response.headers['X-Content-Type-Options']='nosniff'
    return response


@fact_api_bp.get('/metricas')
@acceso
def metrics(local):
    row=db.session.execute(select(func.public.facturacion_metricas_local(bindparam('local')).table_valued(
        'operaciones', 'completadas', 'pendientes', 'requieren_revision', 'espera_max_segundos'
    )),{'local':local}).mappings().one()
    attempts=db.session.execute(select(func.public.facturacion_metricas_intentos(bindparam('local')).table_valued(
        'intentos', 'errores', 'p95_ms'
    )),{'local':local}).mappings().one()
    from flask_jwt_extended import get_jwt
    scaling=None
    if db.session.execute(select(func.public.facturacion_perfil_ve_escalado(get_jwt().get('id_perfil')))).scalar() and db.session.execute(select(func.public.facturacion_escalado_instalado())).scalar() is True:
        state=db.session.execute(select(func.public.facturacion_obtener_escalado().table_valued(
        'id', 'supervisor', 'pid', 'minimo', 'maximo', 'activos', 'objetivo', 'listos',
        'ocupados', 'espera_segundos', 'pausado', 'workers', 'actualizado_en'
    ))).mappings().first()
        scaling=dict(state) if state else None
    return jsonify(**dict(row),ultimas_24_horas=dict(attempts),escalado=scaling)


for rule,handler,methods in [('/<origin>/<int:source>',status,['GET']),('/<origin>/<int:source>',enqueue,['POST']),
    ('/archivos/<uuid:identity>',download,['GET']),('/metricas',metrics,['GET']),
    ('/operaciones/<uuid:identity>/reintentar',retry,['POST'])]:
    salon_fact_api_bp.add_url_rule('/fact-api'+rule,view_func=handler,methods=methods)


@fact_api_bp.after_request
@salon_fact_api_bp.after_request
def private_response(response):
    response.headers['Cache-Control']='private, no-store'
    response.headers['X-Content-Type-Options']='nosniff'
    return response
